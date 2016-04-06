package WWW::PubCrawl::Parser::General;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        for ( $root->look_down('_tag' => 'meta') ) {
            my $name = $_->attr('name');
            next if (! defined $name);
            if ($name eq 'citation_pdf_url') {
                return $_->attr('content');
            }
        }
        return;

    }

    sub _order { 5 } # lower integers get called first

    sub get_name { 'General' }

}

1;
