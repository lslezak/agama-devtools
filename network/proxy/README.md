# Proxy Server

This documentation describes setting up a testing HTTP proxy.

## Plain proxy server

To configure a plain HTTP proxy without authentication follow these steps:

- Install `squid` package: `zypper install squid`
- Edit the `/etc/squid/squid.conf` configuration file, uncomment the `http_access allow localnet`
  line to allow access from local network (from testing VMs)
- Restart the proxy server: `systemctl restart squid.service`
- Make sure the proxy port is open in firewall
  - `firewall-cmd --zone=public --add-service=squid` - open the port in the
    currently running firewall
  - `firewall-cmd --permanent --zone=public --add-service=squid` - make the
    setting permanent so it is activated after reboot automatically
- To test that the proxy correctly works run this command
  `curl -I -s --proxy http://localhost:3128 http://www.suse.com` or  
  just open the proxy URL http://localhost:3128 in a browser. (The displayed
  error message in browser is OK as it does not use the proxy as a proxy.)

## Authenticated proxy server

To create an authenticated proxy which requires user a name and password follow
these steps:

- Install `squid` and `apache2-utils` packages (`zypper install squid apache2-utils`)
- Configure the proxy and the firewall as described above for the plain HTTP proxy
- Create a password database for proxy, run `htpasswd2 -c /etc/squid/squid.pass
  <user_name>`, enter the password for the specified user (the user does not
  need to exist in the system, this is just a proxy user). You can use LDAP,
  PAM, or other backend if needed, see the squid documentation.
- Add these configuration lines at the beginning of the `/etc/squid/squid.conf` file :

```text
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/squid.pass
auth_param basic children 5 startup=5 idle=1
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
acl ncsa_users proxy_auth REQUIRED
http_access allow ncsa_users
```

- Note: Some older squid versions used "/usr/sbin/basic_ncsa_auth" path, change it if needed.
- Restart the proxy server: `systemctl restart squid.service`
- To test that the proxy correctly works run this command `curl -I -s --proxy
  http://<user>:<password>@localhost:3128 http://www.suse.com` (replace
  `<user>:<password>` with the configured credentials)
- When the credentials are missing or are wrong the HTTP proxy returns HTTP
  error code 407 (Proxy Authentication Required).

## Debugging

To confirm that the proxy was really used for the connections you can check the
access log file with:

```sh
tail -f /var/log/squid/access.log
```
