package ImageAssetFromEntry::Plugin;

use strict;
use warnings;

use MT::Asset;
use MT::Asset::Image;
use MT::ObjectAsset;

use HTML::TokeParser;
use File::Spec;
use LWP::Simple;
use Image::Size;

use Data::Dumper;

sub save {
    my ($cb, $app, $obj, $original) = @_;
    my $plugin = $cb->plugin;

    # The image will be in the Entry Body, because that's the location the 
    # XML-RPC publishes to.
    my $text = $obj->text;

    # Search the entry for any images and grab the image src URL. This will 
    # return an array of only the non-local image URLs.
    my @images = _find_images($text, $obj->blog_id);

    foreach my $image (@images) {

        # Save the image locally and turn it into an asset.
        my $asset = _convert_to_asset($image, $obj->blog_id);
        next unless $asset && $asset->id;

        # Update the ObjectAsset table to create the entry-asset link.
        $asset->associate( $obj, 0 );
        
        MT->log({
            level   => MT->model('log')->INFO(),
            blog_id => $obj->blog_id,
            message => "Image Asset From Entry created a new asset, "
                . $asset->label . ", from the image at $image.",
        });

        # Update the image in the entry with the URL of the saved asset.
        # Just a regex to change the old URL to the new URL.
        my $asset_url = $asset->url;
        $text =~ s/$image/$asset_url/g;
    }
    
    # Copy the updated text with new image URL back into the text field, and
    # save that.
    $obj->text( $text );

    # Save the object with the updated text. Also, this is responsible for 
    # putting the $objectasset into effect.
    $obj->save or die $obj->errstr;

    return 1;
}

sub _find_images {
    my ($text, $blog_id) = @_;
    my @images;

    # Give up if this text field is empty.
    return if !$text;
    
    # Grab the blog so that we can compare the the published blog root to 
    # the image's src URL.
    my $blog = MT->model('blog')->load($blog_id);
    my $blog_site_url = $blog->site_url;
    
    # Extract images.
    my $html = HTML::TokeParser->new( \$text );
    while ( my $image_tag = $html->get_tag('img') ) {
        my $image_src = $image_tag->[1]{src};

        # If the image src does not match the $blog_site_url then this is an 
        # image we want to work with and if the image does begin with http: or 
        # https:, then this is an image we want to work with.
        if ($image_src !~ /$blog_site_url/ && $image_src =~ /^https?:/) {
            push @images, $image_src;
        }
    }

    return @images;
}

sub _convert_to_asset {
    my ($image, $blog_id) = @_;
    my $blog = MT->model('blog')->load($blog_id);

    # If the destination folder doesn't exist, create it.
    my $dest_path = File::Spec->catfile($blog->site_path, 'assets');
    my $fmgr = $blog->file_mgr;
    if ( !$fmgr->exists($dest_path) ) {
        $fmgr->mkpath($dest_path)
            or MT->log({
                level   => MT->model('log')->ERROR(),
                blog_id => $blog->id,
                message => "Image Asset From Entry: the destination $dest_path could "
                    . "not be created. " . $fmgr->errstr,
            });
    }

    # Extract the filename from the $image url.
    $image =~ /.*\/(.*)/;
    my $filename = $1;

    # Separate the $filename into the $basename and $ext. ($directories is 
    # always empty.)
    my $basename = $filename;
    $basename =~ s/^(.*)\..*/$1/;
    my $ext = $filename;
    $ext =~ s/.*\.(.*)$/$1/;

    # Use the AssetFileExtensions config directive to check that the filename
    # extension is valid.
    _check_assetfileextensions($ext);

    # Check to see if a file with this name already exists. If it does, update
    # the filename to make it unique and try again.
    my $dest_file_path = File::Spec->catfile($dest_path, $filename);
    my $file_counter = '1';
    while ( $fmgr->exists($dest_file_path) ) {
        $filename = $basename . '_' . $file_counter . '.' . $ext;
        $dest_file_path = File::Spec->catfile($dest_path, $filename);
        $file_counter++;
    }

    # Get the image and save it locally.
    my $image_headers = LWP::Simple::head($image);
    my $http_response = LWP::Simple::getstore( $image, $dest_file_path );

    # If the file was not successfully gotten or saved, report it and give up.
    if ( $http_response != 200 ) {
        MT->log({
            level   => MT->model('log')->ERROR(),
            blog_id => $blog->id,
            message => "Image Asset From Entry could not save the image $image to "
                . "the destination $dest_file_path. HTTP response: "
                . "$http_response.",
        });
        return;
    }

    # Create the asset.
    my $asset = MT->model('asset.image')->new();
    $asset->blog_id( $blog->id );
    my $rel_path = File::Spec->catfile('%r', 'assets', $filename);
    $asset->file_path( $rel_path );
    $asset->url( $rel_path );
    $asset->file_name( $filename );
    $asset->label( $filename );
    $asset->file_ext( $ext );
    $asset->mime_type( $image_headers->{'_headers'}{'content-type'} );

    my ( $w, $h, $id ) = Image::Size::imgsize($dest_file_path);
    $asset->image_width($w);
    $asset->image_height($h);

    $asset->save or die $asset->errstr;

    my $bytes = $image_headers->{'_headers'}{'content-length'};

    MT->run_callbacks(
        'api_upload_image',
        {File       => $dest_file_path,
        file       => $dest_file_path,
        Url        => $asset->url,
        url        => $asset->url,
        Size       => $bytes,
        size       => $bytes,
        Asset      => $asset,
        asset      => $asset,
        Height     => $asset->image_height,
        height     => $asset->image_height,
        Width      => $asset->image_width,
        width      => $asset->image_width,
        Type       => 'image',
        type       => 'image',
        ImageType  => $id,
        image_type => $id,
        Blog       => $blog,
        blog       => $blog}
    );

    return $asset;
}

# Use the AssetFileExtensions config directive to check that the filename
# extension is valid.
sub _check_assetfileextensions {
    my ($ext) = @_;
    my $app = MT->instance;

    if ( my $allow_exts = $app->config('AssetFileExtensions') ) {
        
        # Split the parameters of the AssetFileExtensions configuration 
        # directive into items in an array
        my @allowed = map { 
            if ( $_ =~ m/^\./ ) { qr/$_/i } else { qr/\.$_/i } 
        } split '\s?,\s?', $allow_exts;
        
        # Find the extension in the array
        my @found = grep(/\b$ext\b/, @allowed);

        # If there is no extension or the extension wasn't found in the array
        if ((length($ext) == 0) || ( !@found )) {
            # Just die silently. If the extension wasn't found or doesn't 
            # exist this is probably some malformed HTML.
            return;
        }
    }
}

1;

__END__
