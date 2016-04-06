package WWW::PubCrawl::Parser::ACS;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        for ( $root->look_down('_tag' => 'a') ) {
            my $title = $_->attr('title');
            next if (! defined $title);
            if ($title =~ /view the full text pdf/i) {
                return $base_url . $_->attr('href');
            }
        }
        return;

    }

    sub _order { 6 } # lower integers get called first

    sub get_name { 'ACS' }
}

1;
