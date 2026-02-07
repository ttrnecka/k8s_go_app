# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  
  # Ansible Controller Node
  config.vm.define "ansible-controller" do |controller|
    controller.vm.hostname = "ansible-controller"
    controller.vm.network "private_network", ip: "192.168.56.5"
    
    controller.vm.provider "virtualbox" do |vb|
      vb.name = "ansible-controller"
      vb.memory = "1024"
      vb.cpus = 1
      # Enable time sync with host
      vb.customize ["setextradata", :id, "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled", "0"]
    end
    
    controller.vm.provision "shell", inline: <<-SHELL
      # Update hosts file
      cat >> /etc/hosts <<EOF
192.168.56.5 ansible-controller
192.168.56.10 k8s-master
192.168.56.11 k8s-worker-1
192.168.56.12 k8s-worker-2
EOF

      # Install Ansible
      apt-get update
      apt-get install -y software-properties-common
      add-apt-repository -y ppa:ansible/ansible
      apt-get update
      apt-get install -y ansible git vim chrony

      cat >> /etc/chrony/chrony.conf <<EOF
# Ubuntu NTP servers
pool ntp.ubuntu.com iburst maxsources 4
pool 0.ubuntu.pool.ntp.org iburst maxsources 1
pool 1.ubuntu.pool.ntp.org iburst maxsources 1
pool 2.ubuntu.pool.ntp.org iburst maxsources 2

# Allow the system clock to be stepped in the first three updates
makestep 1.0 -1

# Enable kernel synchronization of the real-time clock (RTC)
rtcsync

# Specify directory for log files
logdir /var/log/chrony
EOF

      # Generate SSH key for Ansible
      if [ ! -f /home/vagrant/.ssh/id_rsa ]; then
        sudo -u vagrant ssh-keygen -t rsa -b 2048 -f /home/vagrant/.ssh/id_rsa -N ""
        chown vagrant:vagrant /home/vagrant/.ssh/id_rsa*
      fi

      # Copy project files to controller
      mkdir -p /home/vagrant/k8s-project
      chown -R vagrant:vagrant /home/vagrant/k8s-project
    SHELL
  end
  
  # Control Plane Node
  config.vm.define "k8s-master" do |master|
    master.vm.hostname = "k8s-master"
    master.vm.network "private_network", ip: "192.168.56.10"
    
    master.vm.provider "virtualbox" do |vb|
      vb.name = "k8s-master"
      vb.memory = "2048"
      vb.cpus = 2
      # Enable time sync with host
      vb.customize ["setextradata", :id, "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled", "0"]
    end
    
    master.vm.provision "shell", inline: <<-SHELL
      # Update hosts file
      cat >> /etc/hosts <<EOF
192.168.56.5 ansible-controller
192.168.56.10 k8s-master
192.168.56.11 k8s-worker-1
192.168.56.12 k8s-worker-2
EOF

      # Enable password authentication for initial setup
      sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
      systemctl restart sshd

      # Install skopeo for image management
      apt-get update
      apt-get install -y skopeo

    SHELL
  end
  
  # Worker Nodes
  (1..2).each do |i|
    config.vm.define "k8s-worker-#{i}" do |worker|
      worker.vm.hostname = "k8s-worker-#{i}"
      worker.vm.network "private_network", ip: "192.168.56.1#{i}"
      
      worker.vm.provider "virtualbox" do |vb|
        vb.name = "k8s-worker-#{i}"
        vb.memory = "2048"
        vb.cpus = 2
        # Enable time sync with host
        vb.customize ["setextradata", :id, "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled", "0"]
      end
      
      worker.vm.provision "shell", inline: <<-SHELL
        # Update hosts file
        cat >> /etc/hosts <<EOF
192.168.56.5 ansible-controller
192.168.56.10 k8s-master
192.168.56.11 k8s-worker-1
192.168.56.12 k8s-worker-2
EOF

        # Enable password authentication for initial setup
        sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
        systemctl restart sshd

        # Install skopeo for image management
        apt-get update
        apt-get install -y skopeo
      SHELL
    end
  end
  
  # Shared provisioning for SSH key distribution
  config.vm.provision "shell", run: "always", inline: <<-SHELL
    # Accept SSH keys automatically (for initial setup)
    mkdir -p /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    chown vagrant:vagrant /home/vagrant/.ssh
  SHELL
  
  # Disable default sync folder
  config.vm.synced_folder ".", "/vagrant", disabled: true
end