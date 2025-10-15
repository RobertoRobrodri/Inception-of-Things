Vagrant.configure("2") do |config|

  config.vm.box = "debian/bookworm64"

  # Carpetas compartidas - montar p1, p2 y p3 dentro de /IoT en la VM
  config.vm.synced_folder "./p1", "/IoT/p1", type: "virtualbox", create: true
  config.vm.synced_folder "./p2", "/IoT/p2", type: "virtualbox", create: true
  config.vm.synced_folder "./p3", "/IoT/p3", type: "virtualbox", create: true

  # Port forwarding
  config.vm.network "forwarded_port", guest: 8888, host: 8888

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 6144
    vb.cpus = 6

    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
    vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
    vb.customize ["modifyvm", :id, "--vtxux", "on"]
    vb.customize ["modifyvm", :id, "--pae", "on"]

    vb.name = "debian-host-nested"
  end

  config.vm.provision "shell", inline: <<-SHELL
    # Configurar entorno no interactivo
    export DEBIAN_FRONTEND=noninteractive

    # Actualizar sistema
    apt-get update
    apt-get upgrade -y

    # Instalar dependencias básicas
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      wget \
      git \
      vim \
      gnupg \
      software-properties-common \
      qemu-kvm \
      libvirt-daemon-system \
      libvirt-clients \
      libvirt-dev \
      bridge-utils \
      build-essential \
      dkms \
      ruby-dev \
      libxslt-dev \
      libxml2-dev \
      zlib1g-dev

    # Actualizar kernel si es necesario
    apt-get install -y linux-image-amd64 linux-headers-amd64

    # Añadir usuario vagrant a los grupos necesarios
    usermod -aG libvirt vagrant
    usermod -aG kvm vagrant

    # Instalar Vagrant
    VAGRANT_VERSION="2.4.1"
    wget https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}-1_amd64.deb
    dpkg -i vagrant_${VAGRANT_VERSION}-1_amd64.deb
    rm vagrant_${VAGRANT_VERSION}-1_amd64.deb

    # Instalar plugin de libvirt para Vagrant (versión compatible)
    vagrant plugin install vagrant-libvirt --plugin-version=0.12.2

    # Iniciar y habilitar libvirt
    systemctl enable libvirtd
    systemctl start libvirtd

    # Verificar instalación
    echo "======================================="
    echo "Verificando instalaciones..."
    echo "======================================="
    if command -v virsh &> /dev/null; then
      echo "✓ libvirt instalado: $(virsh --version)"
    else
      echo "✗ libvirt NO disponible"
    fi

    if command -v vagrant &> /dev/null; then
      echo "✓ Vagrant instalado: $(vagrant --version)"
    else
      echo "✗ Vagrant NO disponible"
    fi
    echo "======================================="

    echo "Provisión completada. Reiniciando para aplicar cambios..."
    sudo reboot
  SHELL
end
