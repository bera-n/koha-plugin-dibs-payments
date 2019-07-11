#!/usr/bin/perl
  
# Copyright 2015 PTFS Europe
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use CGI qw( -utf8 );

use C4::Context;
use C4::Circulation;
use C4::Auth;
use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;
use Koha::Plugin::Com::BibLibre::DIBSPayments;

use XML::LibXML;
use Digest::MD5 qw(md5_hex);

my $paymentHandler = Koha::Plugin::Com::BibLibre::DIBSPayments->new;
my $input = new CGI;
my $statuscode = $input->param('statuscode');
if ($statuscode and $statuscode == 2) {
    my $totalamount = $input->param('totalamount');
    my $transaction_id = $input->param('orderid');

    my $table = $paymentHandler->get_qualified_table_name('dibs_transactions');
    my $dbh   = C4::Context->dbh;
    my $sth   = $dbh->prepare(
        "SELECT borrowernumber, accountlines_ids, amount FROM $table WHERE transaction_id = ?");
    $sth->execute($transaction_id);
    my ($borrowernumber, $accountlines_string, $amount) = $sth->fetchrow_array();
    my @accountline_ids = split(' ', $accountlines_string);
    my $borrower = Koha::Patrons->find($borrowernumber);
    my $lines = Koha::Account::Lines->search(
        { accountlines_id => { 'in' => \@accountline_ids } } )->as_list;
    my $account = Koha::Account->new( { patron_id => $borrowernumber } );
    my $accountline_id = $account->pay(
        {   
            amount     => $amount,
            note       => 'DIBS Payment',                                                                 
            library_id => $borrower->branchcode,                                                         
            lines => $lines,    # Arrayref of Koha::Account::Line objects to pay                         
                                #account_type => $type,  # accounttype code                              
                 #offset_type  => $offset_type,    # offset type code                                    
        }
    ); 

    # Link payment to dibs_transactions
    my $dbh   = C4::Context->dbh;
    my $sth   = $dbh->prepare(
        "UPDATE $table SET accountline_id = ? WHERE transaction_id = ?");
    $sth->execute( $accountline_id, $transaction_id );
    
    # Renew any items as required
    for my $line ( @{$lines} ) {
        my $item = Koha::Items->find( { itemnumber => $line->itemnumber } );

        # Renew if required
        if ( defined( $line->accounttype )
            && $line->accounttype eq "FU" )
        {
            if (
                C4::Circulation::CheckIfIssuedToPatron(
                    $line->borrowernumber, $item->biblionumber
                )
              )
            {
                my ( $can, $error ) =
                  C4::Circulation::CanBookBeRenewed( $line->borrowernumber,
                    $line->itemnumber, 0 );
                if ($can) { 
                    my $datedue =
                      C4::Circulation::AddRenewal( $line->borrowernumber,
                        $line->itemnumber );
                    C4::Circulation::_FixOverduesOnReturn(
                        $line->borrowernumber, $line->itemnumber );
                }
            }
        }
	}


} else {
    warn "notok: $statuscode";
    print "<html><body>notok</body></html>";
}



