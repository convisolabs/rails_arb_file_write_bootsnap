# Exploiting Arbitrary File Write Vulnerability in Restricted Rails Apps via Bootsnap for Remote Code Execution (RCE)

This repository contains a vulnerable application and corresponding exploits to demonstrate a technique for obtaining remote code execution (RCE) through arbitrary file writes in restricted Rails apps via Bootsnap.

You can read the details in this blogpost here.

## Running the vulnerable app

```
cd vulnerable_app
docker build -t my-app .
docker run --rm -p 3000:3000 --name my-app -e RAILS_MASTER_KEY=50584fc86b1efe7e0760f2b28f31744b my-app
```

## Installing required gem for the exploits

```
gem install httparty
```

## Running the exploit

```
ruby xpl.rb
```

## Running the exploit with database

```
ruby xpl_db.rb
```
