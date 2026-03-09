# Fractal Generator Deployment Guide

## Overview
This guide walks you through deploying the Fractal Generator web application on a Kali Linux system. The application consists of a Flask backend that generates fractals, served through NGINX as a reverse proxy.

## Prerequisites
- Kali Linux (or any Debian-based Linux distribution)
- Git installed (`sudo apt install git`)
- Sudo privileges
- Internet connection for dependency installation

---

## Installation Steps

### 1. Clone the Repository
First, clone the repository to your home directory:

```bash
cd /home/kali
git clone https://github.com/School2281/purple_pickleberry.git
```

### 2. Navigate to Project Directory
```bash
cd /home/kali/purple_pickleberry
```

### 3. Make the Deployment Script Executable
```bash
chmod +x fractal_deploy.sh
```

### 4. Run the Deployment Script
Execute the deployment script with sudo privileges:

```bash
sudo ./fractal_deploy.sh
```

> **Note:** After you are done with the unsecure setup
### 5. Make the Securing Script Executable
```bash
chmod +x fractal_safe.sh
```

### 6. Run the Securing Script
Execute the securing script with sudo privileges:

```bash
sudo ./fractal_safe.sh
```
