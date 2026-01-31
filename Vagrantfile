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
      apt-get install -y ansible git vim

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