package WWW::PubCrawl::Parser::JSTAGE;

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
            my @content = $_->content_list();
            if (@content > 0 && $content[0] =~ /Full Text PDF/) {
                return $_->attr('href');
            }
            if (@content > 1 && $content[1] =~ /Full Text PDF/) {
                return $_->attr('href');
            }
        }
        return;

    }

    sub _order { 7 } # lower integers get called first

    sub get_name { 'JSTAGE' }
}

1;
