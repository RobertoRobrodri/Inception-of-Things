Vagrant.configure("2") do |config|

  config.vm.box = "debian/bookworm64"

  # Carpetas compartidas - montar p1, p2 y p3 dentro de /IoT en la VM
  config.vm.synced_folder "./p1", "/IoT/p1", type: "virtualbox", create: true
  config.vm.synced_folder "./p2", "/IoT/p2", type: "virtualbox", create: true
  config.vm.synced_folder "./p3", "/IoT/p3", type: "virtualbox", create: true

  # Port forwarding
  config.vm.network "forwarded_port", guest: 8888, host: 8888

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096
    vb.cpus   = 6

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

    # Instalar dependencias básicas primero
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      wget \
      git \
      vim \
      gnupg \
      software-properties-common

    # Actualizar kernel si es necesario
    apt-get install -y linux-image-amd64 linux-headers-amd64

    # Instalar build-essential y dkms después de tener los headers
    apt-get install -y build-essential dkms

    # Añadir clave GPG de VirtualBox
    wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg

    # Añadir repositorio de VirtualBox
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian bookworm contrib" | tee /etc/apt/sources.list.d/virtualbox.list

    # Instalar VirtualBox
    apt-get update
    apt-get install -y virtualbox-7.0

    # Verificar que los headers estén instalados correctamente
    KERNEL_VERSION=$(uname -r)
    echo "Kernel actual: ${KERNEL_VERSION}"

    if [ ! -d "/lib/modules/${KERNEL_VERSION}/build" ]; then
      echo "Headers del kernel no encontrados, instalando..."
      apt-get install -y linux-headers-${KERNEL_VERSION}
    fi

    # Compilar módulos de VirtualBox
    echo "======================================="
    echo "Compilando módulos de VirtualBox..."
    echo "======================================="
    /sbin/vboxconfig || {
      echo "Error en vboxconfig, intentando de nuevo..."
      apt-get install -y --reinstall linux-headers-${KERNEL_VERSION}
      /sbin/vboxconfig
    }

    # Añadir usuario vagrant al grupo vboxusers
    usermod -aG vboxusers vagrant

    # Instalar Vagrant
    VAGRANT_VERSION="2.4.9"
    wget https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}-1_amd64.deb
    dpkg -i vagrant_${VAGRANT_VERSION}-1_amd64.deb
    rm vagrant_${VAGRANT_VERSION}-1_amd64.deb

    # Cargar módulos de VirtualBox
    modprobe vboxdrv && echo "✓ Módulo vboxdrv cargado" || echo "✗ Error cargando vboxdrv"
    modprobe vboxnetflt && echo "✓ Módulo vboxnetflt cargado" || echo "✗ Error cargando vboxnetflt"
    modprobe vboxnetadp && echo "✓ Módulo vboxnetadp cargado" || echo "✗ Error cargando vboxnetadp"

    # Verificar instalación
    echo "======================================="
    echo "Verificando instalaciones..."
    echo "======================================="
    if command -v VBoxManage &> /dev/null; then
      echo "✓ VirtualBox instalado: $(VBoxManage --version)"
    else
      echo "✗ VirtualBox NO disponible"
    fi

    if command -v vagrant &> /dev/null; then
      echo "✓ Vagrant instalado: $(vagrant --version)"
    else
      echo "✗ Vagrant NO disponible"
    fi
    echo "======================================="

    echo "Provisión completada. Es posible que necesites reiniciar la VM para que los módulos de VirtualBox se carguen correctamente."
    echo "Usa: vagrant reload"
    sudo reboot
  SHELL
end
