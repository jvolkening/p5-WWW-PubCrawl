package WWW::PubCrawl::Parser::Ingenta;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        for ( $root->look_down('_tag' => 'title') ) {
            my @contents = $_->content_list();
            next if ($contents[0] !~ /^ingenta/);

            for ( $root->look_down('_tag' => 'a') ) {
                my $title = $_->attr('title');
                next if (! defined $title);
                if ($title =~ /^PDF download of/i) {
                    return $_->attr('href');
                }
            }
        }
        return;

    }

    sub _order { 1 } # lower integers get called first

    sub get_name { 'Ingenta' }
}

1;
