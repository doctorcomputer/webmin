#!/usr/local/bin/perl
# Stop the LDAP server

require './ldap-server-lib.pl';
&error_setup($text{'stop_err'});
$err = &stop_ldap_server();
&error($err) if ($err);
&webmin_log('stop');
&redirect("");


