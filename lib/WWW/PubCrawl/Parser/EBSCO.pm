package WWW::PubCrawl::Parser::EBSCO;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;
use URI::Escape;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        # Crossref version
        for ( $root->look_down('_tag' => 'a') ) {
            my $title = $_->attr('id');
            next if (! defined $title);
            if ($title eq '_ctl0_contentPh_ejsLink') {
                return $_->attr('href');
            }
        }

        # Direct Access version 
        for ( $root->look_down('_tag' => 'FRAME') ) {
                my $title = $_->attr('NAME');
                next if (! defined $title);
                if ($title eq 'FullTextBody') {
                    return $_->attr('SRC');
                }
        }
        for ( $root->look_down('_tag' => 'body') ) {
                my $title = $_->attr('onload');
                next if (! defined $title);
                next if ($title =~ /\(.*\)/); #probably Javascript functions
                $title = uri_unescape($title);
                $title =~ s/\'//g;
                $title =~ s/document\.location\=/$base_url\/ContentServer\//;
                print "ebsco url: $title\n";
                return $title;
        }
        return;

    }

    sub _order { 4 } # lower integers get called first

    sub get_name { 'EBSCO' }
}

1;
