package WWW::PubCrawl::Parser::Wiley;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        for ( $root->look_down('_tag' => 'iframe') ) {
            my $id = $_->attr('id');
            next if (! defined $id);
            if ($id eq 'pdfDocument') {
                return $_->attr('src');
            }
        }
        return;

    }

    sub _order { 4 } # lower integers get called first

    sub get_name { 'Wiley' }
}

1;
