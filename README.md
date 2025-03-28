# Terraform module for a web service (ECS/ALB/RDS)

## Overview

This is a Terraform module that deploys a web service on ECS with an ALB front end and an RDS backend.

## Features

- ECS based web service
- ALB frontend for access from the Internet
- RDS Backend
- Nat GW for ECS tasks to reach Internet
- Public subnets for ALb & private subnets for ECS/DB

---


