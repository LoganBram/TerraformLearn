#setting up enviroment variable for access and secret keys
variable "my_key_id" {
  type      = string
  sensitive = true
}

variable "my_secret_key" {
  type      = string
  sensitive = true
}



#configure provider
provider "aws" {

  /**us east because setup was done at school, cant change due to keys being 
  region specific**/

  region     = "us-east-1"
  access_key = var.my_key_id
  secret_key = var.my_secret_key
}

#1. create vpc

resource "aws_vpc" "main-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
  Name = "production" }
}

#2. create internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main-vpc.id
}


#3. create custom route table

#defining routes for route table, allows our traffic from subnet we created can get to internet

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.main-vpc.id

  #creates deafult route
  route {
    cidr_block = "0.0.0.0/0"                  #this sends all traffic to wherever this route points to
    gateway_id = aws_internet_gateway.main.id #this is the id of the internet gateway defined above
    #our default route sends all traffic to the internet gateway
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id #same as above
  }

  tags = {
    Name = "Prod"
  }
}


#4. create subnet

resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.main-vpc.id
  cidr_block = "10.0.1.0/24"
  #availability zone, within a region there are multiple data centers
  availability_zone = "us-east-1a" #there is 1b, 1c ...

  tags = {
  Name = "prod-subnet" }
}


#5. associate subnet with route table

#we have subnet & route table but must be associated with each other 

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6. create secruity group to allow port 22,80,443

resource "aws_security_group" "allow_web" {
  name        = "allow_webtraffic"
  description = "Allow webtraffic inbound traffic"
  vpc_id      = aws_vpc.main-vpc.id #got from above by referencing vpc, the usual

  #allowing tcp traffic on port 443
  # from port/ to port, if we did 443 then toport = 447, allowing all traffic from 443 to 447

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #can change what subnets have access to this box,
    #could put in our ip address at our house, or another subnet, 0000, means anyone
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  #changing port for each of the ports
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" #any protocol
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_webtraffic"
  }
}

#7. create network interface with an ip in the subnet from 4

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"] #creates private ip for host
  security_groups = [aws_security_group.allow_web.id]
  #also need public ip for anyone step 8
}


#8 assign elastic ip to network interface from above

#this is reliant on internet gateway
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.main]
}

#9 create ubuntu ec2 instance & install apache

resource "aws_instance" "web-server-instance" {
  ami               = "ami-007855ac798b5175e"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a" #same one we used for subnet, very important, must hardcode it
  #because if we dont it will create a new subnet in a different availability zone
  key_name = "main-key" #this is the key we created in aws

  network_interface {
    device_index         = 0 #refers to the first network interface associated with this instance
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  #important
  #this is the user data, this is what we want to do when we create the instance
  user_data = <<-EOF
        sudo apt update -y
        sudo apt install apache2 -y
        sudo systemctl start apache2
        sudo bash -c "echo your very first webserver> /var/www/html/index.html"
    EOF

  tags = {
    Name = "web-server"
  }

}
