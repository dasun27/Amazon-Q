# Amazon Q usage with Terraform

## Overview

This is an attempt to test how we can use Amazon Q to improve developer productivity for building Terraform modules.

## Features

- ECS based web service
- ALB frontend for access from the Internet
- RDS Backend
- Nat GW for ECS tasks to reach Internet
- Public subnets for ALb & private subnets for ECS/DB

---

## Test Output

### Test 1

```
resource "random_string" "random_name" {
  length  = 5
  special = false
  upper   = false
  lower   = true
}

```

### Test 2

```
resource "random_string" "random_name" {
  length  = 5
  special = false
  upper   = false
  lower   = true
}

```

---

## Results

| TBD                        | TBD                             |
| --------------------------- | --------------------------------------- |
| `TBD`           | TBD                 |
| `TBD`            | TBD                 |


---

## Notes
- **TBD:** TBD

---

## Requirements

| Name      | Version |
| --------- | ------- |
| Terraform | >= 0.13 |
| AWS       | >= 4.9  |

