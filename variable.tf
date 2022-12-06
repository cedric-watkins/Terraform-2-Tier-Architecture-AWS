variable "public_subnet_cidr" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_names" {
  type    = list(string)
  default = ["Public_Subnet_2a", "Public_Subnet_2b"]
}

variable "private_subnet" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "private_subnet_names" {
  type    = list(string)
  default = ["Private_Subnet_2a", "Private_Subnet_2b"]
}

variable "instance_names" {
  type    = list(string)
  default = ["web_2a", "web_2b"]
}

variable "username" {
  type      = string
  default   = "Admin"
  sensitive = "true"
}

variable "password" {
  type      = string
  default   = "pass2022"
  sensitive = "true"
}

