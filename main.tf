provider "google" {
  project = "vf-ng-ca-lab"
  region  = "us-west2"
}

# Main VPC
resource "google_compute_network" "main" {
  name                    = "main"
  auto_create_subnetworks = false
}

resource "google_compute_route" "private_network_internet_route" {
  name             = "private-network-internet"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.main.self_link
  next_hop_gateway = "default-internet-gateway"
  priority         = 100
}



# Public Subnet
resource "google_compute_subnetwork" "public_subnet" {
  name          = "public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-west2"
  network       = google_compute_network.main.id
}

# Private Subnet
resource "google_compute_subnetwork" "private_subnet" {
  name          = "private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-west2"
  network       = google_compute_network.main.id

  depends_on = [
    google_compute_network.main
  ]
}

# Cloud Router
resource "google_compute_router" "router" {
  name    = "main-router"
  network = google_compute_network.main.id
  bgp {
    asn            = 64514
    advertise_mode = "CUSTOM"
  }
}

# NAT Gateway
resource "google_compute_router_nat" "nat" {
  name                               = "main-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = "private-subnet"
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  depends_on = [
    google_compute_subnetwork.private_subnet
  ]
}

# Compute
resource "google_compute_instance" "ansible_host" {
  name         = "ansible-host"
  machine_type = "f1-micro"
  zone = "us-west2-b"

  tags = ["ansible-host"]

  boot_disk {
    initialize_params {
      image = "centos-7-v20210721"
    }
  }

  metadata_startup_script = <<EOT
    sudo yum -y update
    sudo yum -y install ansible
    # curl -fsSL https://get.docker.com -o get-docker.sh && 
    # sudo sh get-docker.sh && 
    # sudo service docker start && 
    # sudo usermod -aG docker $(whoami) &&
    # docker run -p 8080:80 -d nginxdemos/hello

EOT

  network_interface {
    network    = google_compute_network.main.self_link
    subnetwork = google_compute_subnetwork.public_subnet.self_link
    access_config {
      network_tier = "STANDARD"
    }
  }


  depends_on = [
    google_compute_subnetwork.public_subnet
  ]
}

# Firewall
resource "google_compute_firewall" "load_balancer_inbound" {
  name    = "allow-ssh-to-pub-subnet"
  network = google_compute_network.main.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  source_tags = ["ansible-host"]
}