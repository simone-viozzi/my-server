FROM ubuntu:latest

ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install --yes meld \
    			  xauth \ 			  
			  openssh-server \
			  x11vnc \
			  xvfb \
			  fluxbox \
			  gnome-icon-theme \
 			  dbus-x11 \
			  gtk-chtheme

RUN mkdir /var/run/sshd \
    && mkdir /root/.ssh \
    && chmod 700 /root/.ssh \
    && ssh-keygen -A \
    && sed -i "s/^.*PasswordAuthentication.*$/PasswordAuthentication no/" /etc/ssh/sshd_config \
    && sed -i "s/^.*X11Forwarding.*$/X11Forwarding yes/" /etc/ssh/sshd_config \
    && sed -i "s/^.*X11UseLocalhost.*$/X11UseLocalhost no/" /etc/ssh/sshd_config \
    && grep "^X11UseLocalhost" /etc/ssh/sshd_config || echo "X11UseLocalhost no" >> /etc/ssh/sshd_config

COPY ./authorized_keys /root/.ssh/

ENV \
  DEBIAN_FRONTEND="nonintractive" \
  X11VNC_PASSWORD="1234"

RUN mkdir ~/.vnc

RUN x11vnc -storepasswd 1234 ~/.vnc/passwd

#RUN bash -c 'echo "meld" >> /.bashrc'

#WORKDIR /usr/share/meld/

#COPY theme ./theme

#RUN cat theme | cat - meld.css  > temp && mv temp meld.css

#RUN rm theme

WORKDIR /root

RUN touch ~/.Xauthority

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

#ENTRYPOINT ["sh", "-c", "/usr/sbin/sshd && tail -f /dev/null"]
