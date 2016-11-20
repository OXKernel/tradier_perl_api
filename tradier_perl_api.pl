#!/usr/bin/perl
###########################################################################################
# Copyright (C) 2016. Roger Doss. All Rights Reserved.
###########################################################################################
# Contact: OpenSource [at] rdoss.com
###########################################################################################
###########################################################################################
# Permission is granted for use of this software under the terms
# of the MIT License:
###########################################################################################
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
# and associated documentation files (the "Software"), to deal in the Software without restriction, 
# including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
# and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
# subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial 
#portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT 
#LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
#IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
#SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#
###########################################################################################
# References:
#   https://developer.tradier.com/documentation/streaming/get-markets-events
#   Get XML format from here.
#   https://developer.tradier.com/documentation/markets/get-quotes
#   Get XML format from here.
###########################################################################################
# Create an order and cancel an order: DONE, need to test.
# Enter an order. DONE, need to test.
use strict;

use DateTime qw();
use POSIX qw(strftime);
use CGI;
use Data::Dumper;
use JSON;
use LWP::UserAgent;
use XML::Simple;

use threads ('yield',
             'stack_size' => 64*4096,
             'exit' => 'threads_only',
             'stringify');
use threads::shared;
use Thread::Queue qw( );

my $request_q = Thread::Queue->new();

my $YOUR_ACCESS_TOKEN="YOUR_ACCESS_TOKEN";
my $TRADIER_API="https://api.tradier.com/v1";
my $STREAM_TRADIER_API="https://stream.tradier.com/v1";
my $PREVIEW="true";

sub get_profile {
    my $req = HTTP::Request->new( );
    $req->method( "GET" );
    $req->uri( "$TRADIER_API/user/profile" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub get_balances {
    my $req = HTTP::Request->new( );
    $req->method( "GET" );
    $req->uri( "$TRADIER_API/user/balances" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub get_account_id {
    my $response = shift;
    my $ref = XMLin($response, ForceArray => 1);
    my @account_id;
    foreach my $account ( @{ $ref->{'account'} } ) {
        foreach my $ele ( $account->{'account_number'} ) {
            foreach (@$ele) {
               push @account_id,$_; 
            }
        }
    }
    return @account_id;
}

sub get_orders {
    my $account_id = shift;
    my $req = HTTP::Request->new( );
    $req->method( "GET" );
    $req->uri( "$TRADIER_API/accounts/$account_id/orders" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub get_quote {
    my $SYMBOLS=shift; # All capitals symbols that are comma seperated.
    my $req = HTTP::Request->new( );
    $req->method( "GET" );
    $req->uri( "$TRADIER_API/markets/quotes?symbols=$SYMBOLS" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub get_historical_quote {
    my $SYMBOL=shift;   # All capitals symbol.
    my $FREQ=shift;     # "daily", "weekly", "monthly".
    my $START=shift;    # Start YYYY-MM-DD
    my $END=shift;      # End YYYY-MM-DD

    if($FREQ eq "daily"  or
       $FREQ eq "weekly" or
       $FREQ eq "monthly") {
    } else {
        die ("invalid frequency, must be one of daily, weekly or monthly\n");
    }
    my $req = HTTP::Request->new( );
    $req->method( "GET" );
    $req->uri( "$TRADIER_API/markets/history?symbol=$SYMBOL&interval=$FREQ&start=$START&end=$END" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub get_session_id {
    my $req = HTTP::Request->new( );
    $req->method( "POST" );
    $req->uri( "$TRADIER_API/markets/events/session" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    my $rtvl = $response->content();
    my $ref = XMLin($rtvl, ForceArray => 1);
    foreach my $stream ( @{ $ref->{'sessionid'} } ) { # References the inner xml tag, <stream><sessionid></sessionid></stream>, we want sessionid and we get it this way...
        return $stream;
    }
}

sub parse_quote {
    my $XML = shift;
    my $ref = XMLin($XML, ForceArray => 1);
    my %quote;

    foreach my $stream (  @{ $ref->{'type'} } ) {
        $quote{'type'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'change'} } ) {
        $quote{'change'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'change_percentage'} } ) {
        $quote{'change_percentage'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'average_volume'} } ) {
        $quote{'average_volume'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'last_volume'} } ) {
        $quote{'last_volume'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'trade_date'} } ) {
        $quote{'trade_date'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'symbol'} } ) {
        $quote{'symbol'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'desription'} } ) {
        $quote{'description'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'bid'} } ) {
        $quote{'bid'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'bidsz'} } ) {
        $quote{'bidsz'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'bidexch'} } ) {
        $quote{'bidexch'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'biddate'} } ) {
        $quote{'biddate'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'ask'} } ) {
        $quote{'ask'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'asksz'} } ) {
        $quote{'asksz'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'askexch'} } ) {
        $quote{'askexch'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'askdate'} } ) {
        $quote{'askdate'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'exch'} } ) {
        $quote{'exch'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'price'} } ) {
        $quote{'price'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'size'} } ) {
        $quote{'size'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'cvol'} } ) {
        $quote{'cvol'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'date'} } ) {
        $quote{'date'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'open'} } ) {
        $quote{'open'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'high'} } ) {
        $quote{'high'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'low'} } ) {
        $quote{'low'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'close'} } ) {
        $quote{'close'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'prevClose'} } ) {
        $quote{'prevClose'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'prevclose'} } ) {
        $quote{'prevclose'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'volume'} } ) {
        $quote{'volume'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'week_52_high'} } ) {
        $quote{'week_52_high'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'week_52_low'} } ) {
        $quote{'week_52_low'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'bid_date'} } ) {
        $quote{'bid_date'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'ask_date'} } ) {
        $quote{'ask_date'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'open_interest'} } ) {
        $quote{'open_interest'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'underlying'} } ) {
        $quote{'underlying'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'strike'} } ) {
        $quote{'strike'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'contract_size'} } ) {
        $quote{'contract_size'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'expiration_date'} } ) {
        $quote{'expiration_date'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'expiration_type'} } ) {
        $quote{'expiration_type'}=$stream;
    }
    foreach my $stream (  @{ $ref->{'option_type'} } ) {
        $quote{'option_type'}=$stream;
    }
    return %quote;
}

#       print "date=$days[$i]{'date'}\n";
#       print "open=$days[$i]{'open'}\n";
#       print "close=$days[$i]{'close'}\n";
#       print "high=$days[$i]{'high'}\n";
#       print "low=$days[$i]{'low'}\n";
#       print "volume=$days[$i]{'volume'}\n";
 
sub print_historic_quote {
    my $days = shift;
    foreach my $i (@{$days}) {
        print "date=$i->{'date'}\n";
        print "open=$i->{'open'}\n";
        print "close=$i->{'close'}\n";
        print "high=$i->{'high'}\n";
        print "low=$i->{'low'}\n";
        print "volume=$i->{'volume'}\n";
    }
}

sub parse_historic_quote {
    my $XML = shift;
    my $ref = XMLin($XML, ForceArray => 1);
    my @days;

    foreach my $stream (  @{ $ref->{'day'} } ) {
        #print "{$stream}\n";
        #push @days,$stream;
        my $rec = {};
        foreach my $ele ( $stream->{'date'} ) {
            foreach  (@$ele) {
                $rec->{'date'}=$_;
            }
        }
        foreach my $ele ( $stream->{'open'} ) {
            foreach  (@$ele) {
                $rec->{'open'}=$_;
            }
        }
        foreach my $ele ( $stream->{'close'} ) {
            foreach  (@$ele) {
                $rec->{'close'}=$_;
            }
        }
        foreach my $ele ( $stream->{'high'} ) {
            foreach  (@$ele) {
                $rec->{'high'}=$_;
            }
        }
        foreach my $ele ( $stream->{'low'} ) {
            foreach  (@$ele) {
                $rec->{'low'}=$_;
            }
        }
        foreach my $ele ( $stream->{'volume'} ) {
            foreach  (@$ele) {
                $rec->{'volume'}=$_;
            }
        }
        push @days, $rec;
    }

    #print_historic_quote(\@days);
    return \@days; # Array of hashes.
}

sub print_instance_quote {
    my $quotes = shift;
    foreach my $i (@{$quotes}) {
        print "symbol=$i->{'symbol'}\n";
        print "description=$i->{'description'}\n";
        print "exch=$i->{'exch'}\n";
        print "type=$i->{'type'}\n";
        print "change=$i->{'change'}\n";
        print "change_percentage=$i->{'change_percentage'}\n";
        print "volume=$i->{'volume'}\n";
        print "average_volume=$i->{'average_volume'}\n";
        print "last_volume=$i->{'last_volume'}\n";
        print "trade_date=$i->{'trade_date'}\n";
        print "open=$i->{'open'}\n";
        print "high=$i->{'high'}\n";
        print "low=$i->{'low'}\n";
        print "close=$i->{'close'}\n";
        print "prevclose=$i->{'prevclose'}\n";
        print "week_52_high=$i->{'week_52_high'}\n";
        print "week_52_low=$i->{'week_52_low'}\n";
        print "bid=$i->{'bid'}\n";
        print "bidsize=$i->{'bidsize'}\n";
        print "bidexch=$i->{'bidexch'}\n";
        print "bid_date=$i->{'bid_date'}\n";
        print "ask=$i->{'ask'}\n";
        print "asksize=$i->{'asksize'}\n";
        print "askexch=$i->{'askexch'}\n";
        print "ask_date=$i->{'ask_date'}\n";
        print "open_interest=$i->{'open_interest'}\n";
        print "underlying=$i->{'underlying'}\n";
        print "strike=$i->{'strike'}\n";
        print "contract_size=$i->{'contract_size'}\n";
        print "expiration_date=$i->{'expiration_date'}\n";
        print "expiration_type=$i->{'expiration_type'}\n";
        print "option_type=$i->{'option_type'}\n";
    }
}

sub parse_instance_quote {
    my $XML = shift;
    my $ref = XMLin($XML, ForceArray => 1);
    my @quotes;

    foreach my $stream (  @{ $ref->{'quote'} } ) {
        #print "{$stream}\n";
        #push @days,$stream;
        my $rec = {};
        foreach my $ele ( $stream->{'symbol'} ) {
            foreach  (@$ele) {
                $rec->{'symbol'}=$_;
            }
        }
        foreach my $ele ( $stream->{'description'} ) {
            foreach  (@$ele) {
                $rec->{'description'}=$_;
            }
        }
        foreach my $ele ( $stream->{'exch'} ) {
            foreach  (@$ele) {
                $rec->{'exch'}=$_;
            }
        }
        foreach my $ele ( $stream->{'type'} ) {
            foreach  (@$ele) {
                $rec->{'type'}=$_;
            }
        }
        foreach my $ele ( $stream->{'change'} ) {
            foreach  (@$ele) {
                $rec->{'change'}=$_;
            }
        }
        foreach my $ele ( $stream->{'change_percentage'} ) {
            foreach  (@$ele) {
                $rec->{'change_percentage'}=$_;
            }
        }
        foreach my $ele ( $stream->{'volume'} ) {
            foreach  (@$ele) {
                $rec->{'volume'}=$_;
            }
        }
        foreach my $ele ( $stream->{'average_volume'} ) {
            foreach  (@$ele) {
                $rec->{'average_volume'}=$_;
            }
        }
        foreach my $ele ( $stream->{'last_volume'} ) {
            foreach  (@$ele) {
                $rec->{'last_volume'}=$_;
            }
        }
        foreach my $ele ( $stream->{'trade_date'} ) {
            foreach  (@$ele) {
                $rec->{'trade_date'}=$_;
            }
        }
        foreach my $ele ( $stream->{'open'} ) {
            foreach  (@$ele) {
                $rec->{'open'}=$_;
            }
        }
        foreach my $ele ( $stream->{'high'} ) {
            foreach  (@$ele) {
                $rec->{'high'}=$_;
            }
        }
        foreach my $ele ( $stream->{'low'} ) {
            foreach  (@$ele) {
                $rec->{'low'}=$_;
            }
        }
        foreach my $ele ( $stream->{'close'} ) {
            foreach  (@$ele) {
                $rec->{'close'}=$_;
            }
        }
        foreach my $ele ( $stream->{'prevclose'} ) {
            foreach  (@$ele) {
                $rec->{'prevclose'}=$_;
            }
        }
        foreach my $ele ( $stream->{'week_52_high'} ) {
            foreach  (@$ele) {
                $rec->{'week_52_high'}=$_;
            }
        }
        foreach my $ele ( $stream->{'week_52_low'} ) {
            foreach  (@$ele) {
                $rec->{'week_52_low'}=$_;
            }
        }
        foreach my $ele ( $stream->{'bid'} ) {
            foreach  (@$ele) {
                $rec->{'bid'}=$_;
            }
        }
        foreach my $ele ( $stream->{'bidsize'} ) {
            foreach  (@$ele) {
                $rec->{'bidsize'}=$_;
            }
        }
        foreach my $ele ( $stream->{'bidexch'} ) {
            foreach  (@$ele) {
                $rec->{'bidexch'}=$_;
            }
        }
        foreach my $ele ( $stream->{'bid_date'} ) {
            foreach  (@$ele) {
                $rec->{'bid_date'}=$_;
            }
        }
        foreach my $ele ( $stream->{'ask'} ) {
            foreach  (@$ele) {
                $rec->{'ask'}=$_;
            }
        }
        foreach my $ele ( $stream->{'asksize'} ) {
            foreach  (@$ele) {
                $rec->{'asksize'}=$_;
            }
        }
        foreach my $ele ( $stream->{'askexch'} ) {
            foreach  (@$ele) {
                $rec->{'askexch'}=$_;
            }
        }
        foreach my $ele ( $stream->{'ask_date'} ) {
            foreach  (@$ele) {
                $rec->{'ask_date'}=$_;
            }
        }
        foreach my $ele ( $stream->{'open_interest'} ) {
            foreach  (@$ele) {
                $rec->{'open_interest'}=$_;
            }
        }
        foreach my $ele ( $stream->{'underlying'} ) {
            foreach  (@$ele) {
                $rec->{'underlying'}=$_;
            }
        }
        foreach my $ele ( $stream->{'strike'} ) {
            foreach  (@$ele) {
                $rec->{'strike'}=$_;
            }
        }
        foreach my $ele ( $stream->{'contract_size'} ) {
            foreach  (@$ele) {
                $rec->{'contract_size'}=$_;
            }
        }
        foreach my $ele ( $stream->{'expiration_date'} ) {
            foreach  (@$ele) {
                $rec->{'expiration_date'}=$_;
            }
        }
        foreach my $ele ( $stream->{'expiration_type'} ) {
            foreach  (@$ele) {
                $rec->{'expiration_type'}=$_;
            }
        }
        foreach my $ele ( $stream->{'option_type'} ) {
            foreach  (@$ele) {
                $rec->{'option_type'}=$_;
            }
        }
        push @quotes, $rec;
    }

    #print_historic_quote(\@days);
    return \@quotes; # Array of hashes.
}

sub stream_start_clean {
    my $SYMBOLS=shift;
    if(-e "$SYMBOLS.str") {
        unlink "$SYMBOLS.str";
    }
    if(-e "$SYMBOLS.str_close") {
        unlink "$SYMBOLS.str_close";
    }
}

sub get_streaming_quote {
    my $SYMBOLS=shift; # All capitals symbols that are comma seperated.
    my $SESSION=shift; # Session id as obtained from get_session_id
    #print "symbols[$SYMBOLS] session[$SESSION]\n";
    my $req = HTTP::Request->new( );
    $req->method( "POST" );
    $req->uri( "$STREAM_TRADIER_API/markets/events" );
    $req->content_type('application/x-www-form-urlencoded');
    $req->content( "symbols=$SYMBOLS&sessionid=$SESSION&linebreak=true&filter=quote,trade" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    #my $response = $ua->request( $req );
    #return $response->content();
    my $response = $ua->request( $req,
                             sub {
                                my ( $chunk, $res ) = @_;
                                #my $len = $res->content_length;
                                #print "expected length = $len\n";
                                if(-e "$SYMBOLS.str_close") {
                                    $request_q->enqueue("$SYMBOLS.str_close");
                                    die "$SYMBOLS.str closed";
                                }
                                open my $fh, '>>:raw', "$SYMBOLS.str" or die $!;
                                print "$chunk";
                                print $fh "$chunk";
                                close $fh;
                                $request_q->enqueue("$chunk");
                              },
                            );
    print $response->status_line, "\n";
    return $response->content();
}


sub get_order_id {
    my $ORDER_INFO=shift;
    my $ref = XMLin($ORDER_INFO, ForceArray => 1);
    foreach my $id ( @{ $ref->{'id'} } ) { # References the inner xml tag, <stream><sessionid></sessionid></stream>, we want sessionid and we get it this way...
        return $id;
    }
}

sub get_order_status {
    my $ORDER_INFO=shift;
    my $ref = XMLin($ORDER_INFO, ForceArray => 1);
    foreach my $status ( @{ $ref->{'status'} } ) { # References the inner xml tag, <stream><sessionid></sessionid></stream>, we want sessionid and we get it this way...
        return $status; # Want "ok"
    }
}

sub create_order {
    my $SYMBOL=shift; # All capital symbol.
    my $ACCOUNT_ID=shift; # Account id.

    my $CLASS=shift; # equity,option
    my $DURATION=shift; # day,gtc
    my $SIDE=shift; # equity: buy,buy_to_cover,sell,sell_short
                    # option: buy_to_open,buy_to_close,sell_to_open,sell_to_close
    my $QUANTITY=shift; # number of orders.
    my $TYPE=shift; # market,limit,stop,stop_limit
    my $PRICE=shift; # price for limit and stop_limit orders
    my $STOP=shift;  # Stop price in a stop or stop_limit
    my $OPTION_SYMBOL=shift; # required for option order

    my $req = HTTP::Request->new( );
    $req->method( "POST" );
    $req->uri( "$TRADIER_API/accounts/$ACCOUNT_ID/orders" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );
    $req->content_type('application/x-www-form-urlencoded');
    my $payload="";
    if($PREVIEW eq "true") {
        $payload = $payload . "preview=true&";
    }
    if($DURATION eq "day" or
       $DURATION eq "gtc") {
    } else {
        die("invalid duration $DURATION\n");
    }
    if($CLASS eq "equity") {
        if($SIDE eq "buy" or
           $SIDE eq "buy_to_cover" or
           $SIDE eq "sell" or
           $SIDE eq "sell_short") {
        } else {
            die ("invalid side=$SIDE for equity\n");
        }
        if($TYPE eq "market" or
           $TYPE eq "limit"  or
           $TYPE eq "stop"   or
           $TYPE eq "stop_limit") {
        } else {
            die ("invalid trade type for equity\n");
        }
        $payload = $payload . "class=equity&symbol=$SYMBOL&duration=$DURATION&side=$SIDE&quantity=$QUANTITY&type=$TYPE";
        if($TYPE eq "limit" or
           $TYPE eq "stop_limit") {
            if($PRICE eq "") {
                die("invalid price for $TYPE\n");
            }
            $payload = $payload . "&price=$PRICE";
        }
        if($TYPE eq "stop" or
           $TYPE eq "stop_limit") {
            if($STOP eq "") {
                die("invalid stop for $TYPE\n");
            }
            $payload = $payload . "&stop=$STOP";
        }
    } elsif($CLASS eq "option") {
        if($SIDE eq "buy_to_open" or
           $SIDE eq "buy_to_close" or
           $SIDE eq "sell_to_open" or
           $SIDE eq "sell_to_close") {
        } else {
            die ("invalid side=$SIDE for option\n");
        }
        if($TYPE eq "market" or
           $TYPE eq "limit"  or
           $TYPE eq "stop"   or
           $TYPE eq "stop_limit") {
        } else {
            die ("invalid trade type for option\n");
        }
        $payload = $payload . "class=option&symbol=$SYMBOL&duration=$DURATION&side=$SIDE&quantity=$QUANTITY&type=$TYPE";
        if($TYPE eq "limit" or
           $TYPE eq "stop_limit") {
            if($PRICE eq "") {
                die("invalid price for $TYPE\n");
            }
            $payload = $payload . "&price=$PRICE";
        }
        if($TYPE eq "stop" or
           $TYPE eq "stop_limit") {
            if($STOP eq "") {
                die("invalid stop for $TYPE\n");
            }
            $payload = $payload . "&stop=$STOP";
        }
        $payload = $payload . "&option_symbol=$OPTION_SYMBOL\n";
    }
    $req->content( $payload );

    print "$payload\n";
    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();
}

sub cancel_order {
    my $account_id = shift;
    my $order_id = shift;
    my $req = HTTP::Request->new( );
    $req->method( "DELETE" );
    $req->uri( "$TRADIER_API/accounts/$account_id/orders/$order_id" );
    $req->header( "Authorization" => "Bearer $YOUR_ACCESS_TOKEN" );

    my $ua = LWP::UserAgent->new( );
    $ua->agent( 'InetClntApp/3.0' );
    $ua->ssl_opts( SSL_ca_file => 'cert.pem' ); # This works, copied from /cygdrive/c/cygwin64/usr/ssl/cert.pem, runs in Strawberry Perl from DOS prompt.
    my $response = $ua->request( $req );
    return $response->content();

}

sub print_quote {
    my %quote = shift;
    my @name  = keys %quote;
    my @value = values %quote;
    foreach my $i (0 .. $#name) {
        print "key=$name[$i] value=$value[$i]\n";
    }
}

sub stream_reader {
    my $SYMBOLS=shift;
    my $run = 1;
    $SIG{KILL} = sub { die "terminating stream reader for $SYMBOLS\n"; };

    while($run == 1) {
        if(-e "$SYMBOLS.str_close") {
            $run = 0;
        } else {
            my $job = $request_q->dequeue();
            # TODO: Parse the job to see if it has a matching symbol,
            #       Then we can decide what to do with it. Right now,
            #       all symbols are read here.
            #       Alternatively, we can have a seperate kill, and
            #       we can use a common method handler to decide what to
            #       do with the incoming market data.
            my $tid = threads->tid();
            print "tid=$tid [$job]\n";
            if($job eq "$SYMBOLS.str_close") {
                die "$SYMBOLS.str closed";
            }
            my %quote = parse_quote($job);
            print_quote(%quote);

            #sleep(1 + rand(3));
        }
    }
}


sub stream_close {
    my $SYMBOLS=shift;
    my $DELAY=shift;
    my $STREAM_READER=shift;
    print "tester waiting for $DELAY seconds...\n";
    sleep(int($DELAY));
    open my $fh, '>>:raw', "$SYMBOLS.str_close" or die $!;
    print $fh "close\n";
    close $fh;
    $STREAM_READER->kill('KILL');
}

#
# main
#
my $response = get_profile();
#print "$response\n";

$response = get_balances();
#print "$response\n";

# Print array of account numbers...
my @account_id = get_account_id($response);
#foreach (@account_id) {
#    print "$_\n";
#}

# Get orders for first account...
$response = get_orders($account_id[0]);
#print "$response\n";

# *** Instance quotes ***
#$response = get_quote("IBM,MSFT");
#my $quotes = parse_instance_quote($response);
#print_instance_quote($quotes); # Reference to an array of hashes.

#print "$response\n";

# ***Historic Quote handling***
my $end_dt = DateTime->now;
$end_dt->set_time_zone( 'America/New_York' );
my $end_date = $end_dt->ymd;

my $start_dt = DateTime->now->subtract(days => 7); # Look back two days.
$start_dt->set_time_zone( 'America/New_York' );
my $start_date = $start_dt->ymd;
print "$end_date\n";
print "$start_date\n";
$response = get_historical_quote("IBM","daily",$start_date,$end_date);
print "$response\n";

# ***Streaming quotes API (requires multi threading). ***
#$response = get_session_id();
#print "$response\n";

#my $stream = get_streaming_quote("IBM",$response);
#print "$stream\n";

#stream_start_clean('IBM');
#my $thr        = threads->create('get_streaming_quote','IBM',$response);
#my $thr_reader = threads->create('stream_reader','IBM'); # Read the stream.
#my $thr_close  = threads->create('stream_close','IBM','10',$thr_reader); # stream close.
#$thr_reader->detach();
#$thr->join();
#$thr_reader->join();
#$thr_close->join();

# ***Creating orders API. ***
#$response = create_order("IBM",$account_id[0],"equity","day","buy",1,"market","","","");
# my $order_id = get_order_id($response);

# $response = cancel_order($account_id,$order_id);
# my $status = get_order_status($response);
# if ($status eq "ok") { print "success\n"; }
