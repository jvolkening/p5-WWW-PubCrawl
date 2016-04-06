package WWW::PubCrawl::Parser::Springer;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        # First loop through should match here
        for ( $root->look_down('_tag' => 'div') ) {
            my $id = $_->attr('id');
            next if (! defined $id);
            if ($id eq 'PrimaryPdfSection') {
                return $base_url . $_->attr('data-pdfurl');
            }
        }

        # The above sends us to a second page, which we match here
        for ( $root->look_down('_tag' => 'a') ) {
            my $title = $_->attr('title');
            next if (! defined $title);
            if ($title =~ /^Download PDF/i) {
                return $_->attr('pdfurl');
            }
        }
        return;

    }

    sub _order { 7 } # lower integers get called first

    sub get_name { 'Springer' }
}

1;
