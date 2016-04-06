package WWW::PubCrawl::Parser::ScienceDirect;

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
            if ($title eq 'Download PDF') {
                return $_->attr('pdfurl');
            }
        }
        return;

    }

    sub _order { 6 } # lower integers get called first

    sub get_name { 'ScienceDirect' }
}

1;
