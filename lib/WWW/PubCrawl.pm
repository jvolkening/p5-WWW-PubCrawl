package WWW::PubCrawl 0.001;

use 5.012;

use strict;
use warnings;
use autodie;
use Carp;
use Cwd qw/abs_path/;
use File::Copy qw/move/;
use File::Temp;
use Getopt::Long;
use List::MoreUtils qw/any/;

use IO::Handle;
use WWW::Mechanize::GZip;
use HTTP::Cookies::Netscape;
use HTML::TreeBuilder;
use XML::Simple;
use URI::Escape;
use Module::Pluggable::Ordered
    require => 1, sub_name=> 'parsers', search_path =>  ['WWW::PubCrawl::Parser'];

use constant MAX_LOOPS => 2;

sub new {

    my ($class, %args) = @_;

    my $self = bless {}, $class;

    # Read in cookies if provided
    croak "Can't find requested cookie file"
        if (defined $args{cookies} && ! -e $args{cookies});
    my $cookie_jar = defined $args{cookies}
        ? HTTP::Cookies::Netscape->new( file => $args{cookies})
        : HTTP::Cookies->new();

    # Generate browser
    $self->{ua} = WWW::Mechanize::GZip->new(
        agent => 'Midori/1.0',
        cookie_jar => $cookie_jar,
    );

    $self->{proxy} = $args{proxy}
        if (defined $args{proxy});

    if (defined $args{out_dir}) {
        croak "Output directory doesn't exist" if (! -d $args{out_dir});
        $self->{out_dir} = abs_path($args{out_dir});
    }

    if (defined $args{log}) {
        open my $fh, '>', $args{log}
            or die "Failed to open log file for writing";
        autoflush $fh 1;
        $self->{fh_log} = $fh;
    }

    $self->{verbose} = 1 if ($args{verbose});
    $self->{skip_existing} = 1 if ($args{skip_existing});
    $self->{shrink_pdf} = 1 if ($args{shrink_pdf});

    return $self;

}

#my @proxy_blacklist = (
    #'crossref.org',
    #'nih.gov',
    #'wisc.edu',
#);
#my @sources_to_ignore = (
    #'PubMed Central',
    #'Swets Information Services',
    #'OhioLINK Electronic Journal Center',
    #'Ingenta plc',
#);

sub fetch {

    my ($self, $pmid, %args) = @_;

    croak "Bad PubMed ID: $pmid" if ($pmid !~ /^\d{1,16}$/);

    my $result;
    my $source = 'NA';

    my $fn_out = defined $args{out} ? $args{out}
        : defined $self->{out_dir}  ? $self->{out_dir} . "/$pmid.pdf"
        : "$pmid.pdf";
    if ($args{skip_existing} && -e $fn_out) {
        $result = 'exists';;
    }
    else {
        my @sources = $self->_gather_sources( $pmid );
        if (scalar(@sources) < 1) {
            $result = 'no_source_found';
        }
        else {
            for my $src (@sources) {
                $source = $src->[0];
                    warn "\tchecking $source\n" if ($self->{verbose});
                my $response = $self->{ua}->get($src->[1]);
                $result = $self->_parse_content( $response, $fn_out, 0 );
                last if (defined $result && $result =~ /^success\|/);
            }
            $source = join ';', map {$_->[0]} @sources
                if (! defined $result || $result ne 'success');
        }
    }
    $result = $result // 'failed';
    warn "$pmid\t$result\n" if ($self->{verbose});
    print {$self->{fh_log}} "$pmid\t$result\t$source\n"
        if (defined $self->{fh_log});

    return $result;

}

sub _gather_sources {

    my ($self, $pmid) = @_;

    # Fetch list of providers, removing blacklisted and duplicate sources and
    # using PMC as last resort since they frown on automated downloads
    my @provider_list;
    my @urls = (
        "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/elink.fcgi?dbfrom=pubmed&id=$pmid&cmd=prlinks",
        "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/elink.fcgi?dbfrom=pubmed&id=$pmid&cmd=llinks",
    );
    my $pmc;
    my %seen;
    for (@urls) {
        my $response = $self->{ua}->get($_);
        return "e-utils error" if ($response->content_type ne 'text/xml');
        my $ref = XMLin($response->content(),,ForceArray => ['ObjUrl']);
        if (defined $ref->{LinkSet}->{IdUrlList}->{IdUrlSet}->{ObjUrl}) {
            for my $provider ( @{$ref->{LinkSet}->{IdUrlList}->{IdUrlSet}->{ObjUrl}} ) {

                my $name = $provider->{Provider}->{Name};
                my $url = $provider->{Url};
                next if ($seen{$name});
                next if ($provider->{Category} ne 'Full Text Sources');
                $pmc = [$name,$url] if ($name eq 'PubMed Central');
                next if any {$name =~ /$_/i} @{ $self->{sources_to_ignore} };
                push @provider_list, [$name,$url];
                $seen{$name} = 1;

            }
        }
    }
    push @provider_list, $self->_try_crossref($pmid);
    push @provider_list, $pmc if (defined $pmc); # last resort

    return @provider_list;

}

sub _parse_content {

    my ($self, $response, $fn, $loop_count) = @_;
    ++$loop_count;
    warn "\t\t$loop_count\n";

    #check to see if a PDF was returned
    if ($response->content_type eq 'application/pdf') {
        $self->_write_pdf( $response => $fn );
        my $url = $response->request->uri();
        return "success|$url";
    }
    return "e-utils error" if ($response->content_type ne 'text/html');

    # If we get here, the result was html and not PDF, so try to extract next link level
    my $return;
    my $url = $self->_extract_url( $response );
    if (defined $url) {
        #make all URLs absolute
        if ($url !~ /^http/i) {
            my $curr_loc = $response->base;
            if ($url =~ /^\//) {
                $curr_loc->path( $url );
            }
            else {
                $curr_loc->path( $curr_loc->path . "/$url" );
            }
            $url = $curr_loc;
        }
        $url = uri_unescape( $url );
        if ($loop_count > MAX_LOOPS) {
            return if ( $self->_is_proxied( $url ) );
            $url = $self->_add_proxy($url);
            $loop_count = 0;
        }
    }
    else {
        # No URL was returned, so try proxy if not already
        my $base = $response->base;
        return if ($self->_is_proxied( $base ));
        $url = $self->_add_proxy( $base );
    }
    warn "\tfetching $url\n" if ($self->{verbose});
    my $new_response = $self->{ua}->get( $url );
    $return = $self->_parse_content( $new_response, $fn, $loop_count );
}

sub _is_proxied {

    #checks to see if host is already proxied
    my ($self, $url) = @_;
    my $obj = URI->new( $url );
    my $host = $obj->host;
    return 1 if (! defined $self->{proxy});
    return 1 if (any {$host =~ /$_$/} @{ $self->{proxy_blacklist} });
    return 1 if ($host =~ /$self->{proxy}$/i);
    return 0;

}

sub _add_proxy {

    #adds proxy to end of hostname
    my ($self, $url) = @_;
    my $obj = URI->new( $url );
    my $host = $obj->host;
    return "$obj" if (! defined $self->{proxy});
    return "$obj" if ($host =~ /$self->{proxy}$/i);

    $obj->host( $obj->host . ".$self->{proxy}" );
    return "$obj";

}

sub _write_pdf {

    my ($self, $response, $fn) = @_;

    my ($tmp_fh, $tmp_name) = File::Temp::tempfile();
    binmode $tmp_fh;
    print {$tmp_fh} $response->content;
    close $tmp_fh;
    if ($self->{shrink_pdf}) {
        my $result = system ("gs -dBATCH -dSAFER -q -dNOPAUSE -sDEVICE=pdfwrite -dPDFSETTINGS=/screen -sOutputFile=$fn $tmp_name");
        unlink $tmp_name;
        die "ghostscript error: $fn: $result" if ($result != 0);
    }
    else {
        move($tmp_name => $fn);
    }

    return;

}

sub _extract_url {

    my ($self, $response) = @_;

    my $u1 = $self->{ua}->uri();
    return if ($u1 !~ /^http/i);
    my $base_url = $u1->scheme() . '://' . $u1->host();

    my $root = HTML::TreeBuilder->new_from_content( $response->content );

    # Read in parser module files, sort by numeric prefix, and remove prefix
    for my $parser (WWW::PubCrawl->parsers_ordered()) {
        my $name = $parser->get_name();
        warn "\t\ttrying $name...\n" if ($self->{verbose} > 2);
        my $url = $parser->extract_url( $root, $base_url );
        if (defined $url) {
            $root->delete;
            warn "\tMATCHED $name\n" if ( $self->{verbose} );
            return $url; 
        }
    }
    $root->delete;

    return undef;

}

sub _try_crossref {

    my ($self, $pmid) = @_;

    my $response = $self->{ua}->get("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=$pmid&retmode=xml");
    my $ref = XMLin($response->content(),ForceArray => ['Author','ArticleId']);
    my %keys = (
        'author' => 'rft.au',
        'date'   => 'rft.date',
        'pages'  => 'rft.pages',
        'issn'   => 'rft.issn',
        'issue'  => 'rft.issue',
        'vol'    => 'rft.volume',
        'journal' => 'rft.jtitle',
        'title'   => 'rft.atitle',
    );

    #prefer DOI resolution
    if (defined $ref->{PubmedArticle}->{PubmedData}->{ArticleIdList}->{ArticleId}) {
        for (@{ $ref->{PubmedArticle}->{PubmedData}->{ArticleIdList}->{ArticleId} }) {
            if ($_->{IdType} eq 'doi') {
                my $doi = $_->{content};
                return ['DOI',"http://dx.doi.org/$doi"];
            }
        }
    }

    #otherwise create a CrossRef query 
    my $crossref_url = "http://crossref.org/openurl?url_ver=Z39.88-2004&ctx_ver=Z39.88-2004&rfr_id=info:sid%2Fzotero.org:2&rft_id=info:pmid%2F$pmid";
    if (defined $ref->{PubmedArticle}->{MedlineCitation}->{Article}) {
        my $article = $ref->{PubmedArticle}->{MedlineCitation}->{Article};
        if (defined $article->{Pagination}->{MedlinePgn}) {
            $crossref_url .= "\&$keys{'pages'}=" . $article->{Pagination}->{MedlinePgn};
        }
        if (defined $article->{AuthorList}->{Author}) {
            my $author_count = 0;
            for ( @{ $article->{AuthorList}->{Author} } ) {
                if ($author_count == 0) {
                    $crossref_url .= "\&rft.aufirst=$_->{ForeName}";
                    $crossref_url .= "\&rft.aulast=$_->{LastName}";
                }
                $crossref_url .= "\&$keys{'author'}=$_->{ForeName} $_->{LastName}";
                ++$author_count;
            }
        }
        if (defined $article->{Journal}->{Title}) {
            $crossref_url .= "\&$keys{'journal'}=" . $article->{Journal}->{Title};
        }
        if (defined $article->{Journal}->{JournalIssue}->{Volume}) {
            $crossref_url .= "\&$keys{'vol'}=" . $article->{Journal}->{JournalIssue}->{Volume};
        }
        if (defined $article->{Journal}->{JournalIssue}->{Issue}) {
            $crossref_url .= "\&$keys{'issue'}=" . $article->{Journal}->{JournalIssue}->{Issue};
        }
        if (defined $article->{Journal}->{JournalIssue}->{PubDate}->{Year}) {
            $crossref_url .= "\&$keys{'date'}=" . $article->{Journal}->{JournalIssue}->{PubDate}->{Year};
        }
        if (defined $article->{ArticleTitle}) {
            $crossref_url .= "\&$keys{'title'}=" . $article->{ArticleTitle};
        }
        if (defined $article->{Journal}->{ISSN}->{content}) {
            $crossref_url .= "\&$keys{'issn'}=" . $article->{Journal}->{ISSN}->{content};
        }
        $crossref_url .= "&pid=zter:zter321";
        return ['CrossRef',$crossref_url];
    }
    return;
}

1;
