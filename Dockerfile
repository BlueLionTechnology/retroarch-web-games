# Run RetroArch Web Player in a container
#
# docker run --rm -it -d -p 8080:80 retroarch-web-nightly
#

# Stage 1: Builder
FROM ubuntu:latest AS builder

#User Settings for VNC
ENV USER=root
ENV PASSWORD=password1

#Variables for installation
ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true
ENV XKB_DEFAULT_RULES=base
    

#Install dependencies
RUN apt-get update && \
    echo "tzdata tzdata/Areas select America" > ~/tx.txt && \
    echo "tzdata tzdata/Zones/America select New York" >> ~/tx.txt && \
    debconf-set-selections ~/tx.txt
RUN apt-get install -y \
    ca-certificates \
    unzip \
    sed \
    p7zip-full \
    coffeescript \
    xz-utils \
    nginx \
    wget \
    curl \
    vim \
    nano \
    parallel \
    git \
    python3 \
    python3-pip \
    lbzip2 \
    gnupg \
    gnupg2
RUN apt-get install -y \
    apt-transport-https \
    software-properties-common \
    ratpoison \
    novnc \
    websockify \
    libxv1 \
    xauth \
    x11-utils \
    xorg \
    tightvncserver
RUN apt-get install -y \
#    libegl1-mesa \
    x11-xkb-utils \
    bzip2 \
    gstreamer1.0-plugins-good \
    gstreamer1.0-pulseaudio \
    gstreamer1.0-tools
RUN apt-get install -y \
    libglu1-mesa \
    libgtk2.0-0 \
    libncurses-dev \
#    libncursesw5 \
    libopenal1 \
    libsdl-image1.2 \
    libsdl-ttf2.0-0 \
    libsdl1.2debian \
    libsndfile1 \
    pulseaudio \
    supervisor \
    ucspi-tcp \
    build-essential \
    ccache
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download the necessary .deb packages from the specified URLs
RUN wget https://launchpad.net/ubuntu/+archive/primary/+files/libegl1-mesa_23.0.4-0ubuntu1~22.04.1_amd64.deb -O /tmp/libegl1-mesa.deb && \
    wget https://launchpad.net/ubuntu/+archive/primary/+files/libgl1-mesa-glx_23.0.4-0ubuntu1~22.04.1_amd64.deb -O /tmp/libgl1-mesa-glx.deb

# Install the downloaded packages
RUN dpkg -i /tmp/libegl1-mesa.deb /tmp/libgl1-mesa-glx.deb || true

# Install any missing dependencies
RUN apt-get update && apt-get install -y -f && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clean up downloaded .deb files
RUN rm -f /tmp/libegl1-mesa.deb /tmp/libgl1-mesa-glx.deb

#Copy the files for audio and NGINX
COPY default.pa client.conf /etc/pulse/
COPY nginx.conf /etc/nginx/
COPY webaudio.js /usr/share/novnc/core/

# Install RetroArch from Debian repositories
RUN apt-get update && \
    add-apt-repository ppa:libretro/stable && \
    apt-get install -y retroarch libretro-* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


#Inject code for audio in the NoVNC client
RUN sed -i "/import RFB/a \
      import WebAudio from '/core/webaudio.js'" \
    /usr/share/novnc/app/ui.js \
 && sed -i "/UI.rfb.resizeSession/a \
        var loc = window.location, new_uri; \
        if (loc.protocol === 'https:') { \
            new_uri = 'wss:'; \
        } else { \
            new_uri = 'ws:'; \
        } \
        new_uri += '//' + loc.host; \
        new_uri += '/audio'; \
      var wa = new WebAudio(new_uri); \
      document.addEventListener('keydown', e => { wa.start(); });" \
    /usr/share/novnc/app/ui.js
				
#Install VirtualGL and TurboVNC		
RUN  wget https://gigenet.dl.sourceforge.net/project/virtualgl/3.1/virtualgl_3.1_amd64.deb && \
        wget https://zenlayer.dl.sourceforge.net/project/turbovnc/3.0.3/turbovnc_3.0.3_amd64.deb && \
        dpkg -i virtualgl_*.deb && \
        dpkg -i turbovnc_*.deb && \
        mkdir ~/.vnc/ && \
        mkdir ~/.dosbox && \
        echo $PASSWORD | vncpasswd -f > ~/.vnc/passwd && \
        chmod 0600 ~/.vnc/passwd && \
        echo "set border 1" > ~/.ratpoisonrc  && \
        echo "exec retroarch">> ~/.ratpoisonrc && \
        openssl req -x509 -nodes -newkey rsa:2048 -keyout ~/novnc.pem -out ~/novnc.pem -days 3650 -subj "/C=US/ST=NY/L=NY/O=NY/OU=NY/CN=NY emailAddress=email@example.com"

#MKDir for ROMS
RUN mkdir /roms

#Copy in RetoArch config to remap keys
COPY retroarch.cfg /root/.config/retroarch/retroarch.cfg

# Download and install RetroArch Web Player
ENV ROOT_WWW_PATH /var/www/html
WORKDIR /var/www/html
# COPY setup_retroarch.sh /tmp/setup_retroarch.sh
# RUN chmod +x /tmp/setup_retroarch.sh
# RUN bash /tmp/setup_retroarch.sh ${ROOT_WWW_PATH}

# Install Python dependencies for InternetArchive script
RUN pip3 install --upgrade pip
RUN pip3 install requests typer rich
COPY InternetArchive.py /tmp/InternetArchive.py

# Run the InternetArchive script
RUN chmod +x /tmp/InternetArchive.py
RUN python3 /tmp/InternetArchive.py

COPY sort_mkdir.sh /tmp/sort_mkdir.sh

# Sort
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - GameBoy"
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - GameBoy Advance"
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - GameBoy Color"
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - Nintendo 64"
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - Nintendo Entertainment System"
RUN bash /tmp/sort_mkdir.sh "/roms/Nintendo - Super Nintendo Entertainment System"

COPY entrypoint.sh /

EXPOSE 80
#CMD ["sh", "/entrypoint.sh"]

#Copy in supervisor configuration for startup
COPY supervisord.conf /etc/supervisor/supervisord.conf
ENTRYPOINT [ "supervisord", "-c", "/etc/supervisor/supervisord.conf" ]
