FROM fedora:latest
LABEL Name=unbound Version=0.0.1 
RUN dnf makecache && dnf update -y \
  && dnf install -y pigz make wget tar unbound \
  && dnf clean all

EXPOSE 53
EXPOSE 53/udp
#ENV SHA256SUM_UNBOUND="4e7bd43d827004c6d51bef73adf941798e4588bdb40de5e79d89034d69751c9f"
  
#RUN wget https://unbound.net/downloads/unbound-1.6.7.tar.gz -O /tmp/unbound-1.6.7.tar.gz \
#  &&  \
#  && cd /tmp/ \
#  && echo $SHA256SUM_UNBOUND /tmp/unbound-1.6.7.tar.gz | sha256sum -c - \
#  && tar -I pigz -xvf unbound-1.6.7.tar.gz -C /tmp/unbound \
#  && rm /tmp/unbound-1.6.7.tar.gz \
#  && cd unbound \
#  && make install
RUN wget -S -N https://www.internic.net/domain/named.cache -O /etc/unbound/root.hints

ADD unbound.conf /etc/unbound/unbound.conf
CMD [ "unbound", "-c", "/etc/unbound/unbound.conf"]