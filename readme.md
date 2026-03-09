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
git clone https://github.com/yourusername/purple_pickleberry.git
