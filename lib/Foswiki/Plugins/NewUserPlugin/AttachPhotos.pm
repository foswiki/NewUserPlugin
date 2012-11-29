# Contrib for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::NewUserPlugin::AttachPhotos;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Sandbox ();

our $defaultPhotoDir = '/tmp';
our $debug = 0;

sub writeDebug {
  return unless $debug;
  print STDERR 'AttachPhotos - '.$_[0]."\n";
}

sub writeWarning {
  writeDebug('WARNING: '.$_[0]);
}

sub handle {
  my $session = shift;

  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    Foswiki::Plugins::DBCachePlugin::disableSaveHandler();
  }

  my $query = $session->{request};
  my $mapping = $session->{users}{mapping};
  my $passwordManager = $mapping->{passwords};
  my $usersWeb = $Foswiki::cfg{UsersWebName};

  die "can't fetch users" unless $passwordManager->canFetchUsers;

  my $photoDir = $query->param("dir") || $defaultPhotoDir;
  $debug = Foswiki::Func::isTrue($query->param("debug"));

  die "photoDir=$photoDir does not exist" unless -d $photoDir;

  writeDebug("photoDir=$photoDir");

  my $photos = cacheUserPhotos($photoDir); 

  my $it = $passwordManager->fetchUsers();
  my $count = 0;
  while ($it->hasNext()) {
    my $loginName = $it->next();
    my $wikiName = Foswiki::Func::userToWikiName($loginName, 1);
    writeDebug("checking loginName=$loginName, wikiName=$wikiName");
    unless (Foswiki::Func::topicExists($usersWeb, $wikiName)) {
      writeDebug("no user topic found for $loginName (wikiName=$wikiName)... skipping");
      next;
    }

    my $photo = $photos->{$loginName};
    unless (defined $photo) {
      writeDebug("no photo for $loginName ... skipping");
      next;
    }

    my ($meta) = Foswiki::Func::readTopic($usersWeb, $wikiName);
    my @attachments = $meta->find('FILEATTACHMENT');

    my $found = 0;
    foreach my $attachment (@attachments) {
      my $attachmentName = $attachment->{name};
      if ($attachmentName eq $photo->{name}) {
	$found = 1;
	last;
      }
    }

    if ($found) {
      writeDebug("photo $photo->{name} is already attached to $wikiName ... skipping");
      next;
    }
    my @stats = stat $photo->{file};
    my $fileSize = $stats[7] || 0;
    my $fileDate = $stats[9] || 0;

    writeDebug("attaching photo $photo->{file} (size=$fileSize) for $loginName to $usersWeb.$wikiName");

    my $error = Foswiki::Func::saveAttachment($usersWeb, $wikiName, $photo->{name}, { 
      file => $photo->{file},
      filesize => $fileSize,
      size => $fileSize,
      filedate => $fileDate,
      comment => 'attached automatically',
      hide => 1 
    });

    die $error if $error;

    $count++;
  }

  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    Foswiki::Plugins::DBCachePlugin::enableSaveHandler();
  }

  writeDebug("processed $count user topics");
}

sub cacheUserPhotos {
  my ($photoDir, $loginNamePattern) = @_;

  my %photos = ();
  opendir(DIR, $photoDir) || die "can't open photoDir";
  while (my $file = readdir(DIR)) {
    next if $file =~ /^\./;
    next unless $file =~ /\.(jpe?g|gif|png|bmp)$/i;

    # untaint
    $file = Foswiki::Sandbox::untaintUnchecked($file);

    my $loginName = $file;
    if ($loginNamePattern && $file =~ /$loginNamePattern/) {
      if (defined $1) {
        $file = $1
      }
    } 

    $loginName =~ s/\..*$//; # strip off file extension

    if (defined $photos{$loginName}) {
      my $msg = "user $loginName already has got $photos{$loginName}{name}";
      if ($file =~ /^DETIS/) { # SMELL: client specific
	writeDebug("$msg ... using $file instead");
      } else {
	writeDebug("$msg ... skipping $file");
	next;
      }
    }

    my $filePath = $photoDir."/".$file;
    #writeDebug("found photo for $loginName in $filePath");

    $photos{$loginName} = {
      name => $file,
      file => $filePath,
    }
  }
  closedir(DIR);
 
  return \%photos;
}

1;

