# Image Asset from Entry Overview

The Image Asset from Entry plugin for Melody and Movable Type will look in the
Entry Body for a non-local image URL. If found, that image URL is used to 
create a new image asset in Melody. An asset-entry association is created (to
add the asset to the Entry Asset Manager). The resulting asset URL can replace
the original, or the original URL can simply be removed. Lastly, the new asset
can be associated with an Image Custom Field.

I wrote this plugin specifically to help me publish my photos on Flickr to my
blog: when an entry is published through the XML-RPC API to the blog, normally
the Flickr image URL is displayed in the entry.

This plugin works for entries created through the API, and also works when on
the Edit Entry screen: save an entry and the Entry Body is reviewed for any
non-local image URLs that can be converted into image assets.

Take note that this plugin makes it easy to accidentally steal content: any
image linked on another site will be saved to your site. For my use -- saving
*my* photos to *my* blog -- this isn't a concern, however it's something to be
aware of.

# Prerequisites

Melody 1.0 or greater

# Installation

The latest version of the plugin can be downloaded from the its
[Github repo](https://github.com/danwolfgang/mt-plugin/image-asset-from-entry). 
[Packaged downloads](https://github.com/danwolfgang/mt-plugin/image-asset-from-entry/downloads) are also available if you prefer.

Installation follows the [standard plugin installation](http://tinyurl.com/easy-plugin-install) procedures.

# Use

Publish an entry through the API or save an entry through Melody's
administrative interface.

# License

This plugin is licensed under the same terms as Perl itself.
