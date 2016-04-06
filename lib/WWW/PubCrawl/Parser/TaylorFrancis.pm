package WWW::PubCrawl::Parser::TaylorFrancis;

# v0.0.1 - last updated 2012.01.19

use strict;
use warnings;
use Class::Std;

# Begin class definition
{

    sub extract_url {

        my ($self, $root, $base_url) = @_;

        for ( $root->look_down('_tag' => 'a') ) {
            my $class = $_->attr('class');
            next if (! defined $class);
            if ($class eq 'pdf') {
                my @content = $_->content_list();
                if (@content > 0 && $content[0] eq 'Download full text') {
                    return  $_->attr('href');
                }
            }
        }
        return;

    }

    sub _order { 6 } # lower integers get called first

    sub get_name { 'TaylorFrancis' }
}

1;
