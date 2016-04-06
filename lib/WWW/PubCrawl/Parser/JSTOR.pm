package WWW::PubCrawl::Parser::JSTOR;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        # The above sends us to a second page, which we match here
        for ( $root->look_down('_tag' => 'a') ) {
            my $title = $_->attr('class');
            next if (! defined $title);
            if ($title eq 'pdflink') {
                return $_->attr('href');
            }
        }
        return;

    }

    sub _order { 6 } # lower integers get called first

    sub get_name { 'JSTOR' }
}

1;
