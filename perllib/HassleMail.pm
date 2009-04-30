#!/usr/bin/perl
#
# HassleMail.pm:
# Common code for hassleme incoming mail handling.
#
# Copyright (c) 2009 UK Citizens Online Democracy. All rights reserved.
# Email: louise@mysociety.org; WWW: http://www.mysociety.org
#
# $Id: HassleMail.pm,v 1.4 2009-04-30 16:45:56 louise Exp $
#

package HassleMail;

use strict;
require 5.8.0;

# Horrible boilerplate to set up appropriate library paths.
use FindBin;
use lib "$FindBin::Bin/../perllib";
use lib "$FindBin::Bin/../../perllib";
use mySociety::Config;
use Hassle;

BEGIN {
    mySociety::Config::set_file("$FindBin::Bin/../conf/general");
}
use mySociety::HandleMail;

# Don't print diagnostics to standard error, as this can result in bounce
# messages being generated (only in response to non-bounce input, obviously).
mySociety::SystemMisc::log_to_stderr(0);

use constant MAIL_LOG_PREFIX => mySociety::Config::get('HM_MAIL_LOG_PREFIX'); 

#----------------------
sub mark_as($%){
    my ($destination, $data) = @_;
    my %data = %{$data};
    my $mail = join("\n", @{$data{lines}});
    open FILE, ">>", MAIL_LOG_PREFIX . $destination;
    print FILE $mail;
    close FILE; 
}
#----------------------
sub mark_deleted($$$){
    my ($recipient, $data, $bounced_address) = @_;
    my $email = $bounced_address || $recipient;
    if ($email){
        # delete_recipient($email);
        mark_as('deleted', $data);
    }else{
        mark_as('unparsed', $data);
    }
}

#----------------------
sub handle_dsn_bounce($$$){
    my ($r, $data, $bounced_address) = @_;
    my %attributes = %{$r};
    my $status = $attributes{status};
    if ($status !~ /^5\./ || $status eq '5.2.2'){
        mark_as('ignored', $data);
    }else{
        mark_deleted($attributes{recipient}, $data, $bounced_address);
    }
}
#----------------------
sub handle_non_dsn_bounce($$$){
    my ($attributes, $data, $bounced_address) = @_;
    my %attribute_hash = %{$attributes};
    if (!$attribute_hash{problem}){
        mark_as('unparsed', $data);
        return;
    }
    my $err_type = mySociety::HandleMail::error_type($attribute_hash{problem});
    if ($err_type == mySociety::HandleMail::ERR_TYPE_PERMANENT){
        mark_deleted($attribute_hash{email_address}, $data, $bounced_address);
    }else{
        mark_as('ignored', $data);  
    }
}
#----------------------
sub handle_bounce($$){
    my ($data, $bounced_address) = @_;
    my %data_hash = %{$data};
    my @lines = @{$data_hash{lines}};

    my $r = mySociety::HandleMail::parse_dsn_bounce(\@lines);
    if (!$r){
       $r = mySociety::HandleMail::parse_ill_formed_dsn_bounce(\@lines);
    }

    if ($r){
        handle_dsn_bounce($r, \%data_hash, $bounced_address);
    }else{
        my %attributes = mySociety::HandleMail::parse_bounce(\@lines);
        handle_non_dsn_bounce(\%attributes, \%data_hash, $bounced_address);    
    }
}
#----------------------
sub handle_non_bounce_reply($){
    my ($data) = @_;
    mark_as('ignored', $data);
}
#----------------------
sub handle_incoming($){
    my ($data) = @_;
    my %data = %{$data};
    
    if (!$data{is_bounce_message}) {
        handle_non_bounce_reply(\%data);
    }else{
        my $bounce_recipient = mySociety::HandleMail::get_bounce_recipient($data{message});
        my $bounced_address = get_bounced_address($bounce_recipient);
        handle_bounce(\%data, $bounced_address);
    }
}
#----------------------
1;