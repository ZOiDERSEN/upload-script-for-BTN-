require $main::path."/functions/upload_tl.config.pm";

sub upload_tl {

	my $name=shift; # Torrent name from database
	my $category=shift; # Category ID
	my $description=shift; # Description file path
	my $torrent=shift;  # Torrent file path
	my $nfo=shift; # NFO file path
	my $to_tracker=shift; # tracker code (for example: fano)
	my $defname=shift; # Filename from database
	my $defhash=shift; # Download torrent file info hash
	my $config=shift;

	my $r=ClientFunctions->new('upload', 'tl', $config);

	###################################
	# Requestlg upload page before sending POST data
	# This should be used to bypass some session verification checks
	my $eh=$r->get("http://www.torrentleech.org/upload");
	return 0 if($eh==0);

	###################################
	# Search for nologin
	my $match_nologin=qr/<input name="login"/ms;
    my $nologin_matches=$r->match('nologin', $match_nologin);
    if($nologin_matches!=0 and not defined $config->{cookies}->{cookie_tl}){
        $r->err('Can not continue without login, trying to login!');
        $r->form_new;
        $r->form_add('login', 'submit');
        $r->form_add('remember_me', 'on');
        $r->form_add('username', $config->{cookies}->{user_tl});
        $r->form_add('password', $config->{cookies}->{pass_tl});
        $eh=$r->post("http://www.torrentleech.org/user/account/login/");
        return 0 if($eh==0);
        $nologin_matches=$r->match('nologin', $match_nologin);
        if($nologin_matches!=0){
                $r->err('Can not continue without login, aborting!');
                return 0;
        }
        $eh=$r->get("http://www.torrentleech.org/upload");
        return 0 if($eh==0);
    }elsif($nologin_matches!=0){
        $r->err('Can not continue without login, aborting!');
        return 0;
    }

	###################################
	# Search for original NFO that comes with torrent
	$nfo=$r->find_nfo($torrent, $nfo, $config->{paths}->{download_dir});
	# Read description	
    my $descr_txt=$r->read_file($description);
    if($descr_txt eq $config->{tuper}->{no_descr_txt}){
        $descr_txt=$r->read_file($nfo);
    }

    use Net::BitTorrent::File;
    my $fromfile = new Net::BitTorrent::File($torrent);
    delete($fromfile->{data}{"announce-list"});
    delete($fromfile->{data}{"announce"});
    $fromfile->{data}{"comment"}=";)";
    $fromfile->announce('http://tracker.torrentleech.org:2710/a/'.$config->{cookies}->{passkey_tl}.'/announce');
    my $newtorr=$config->{paths}->{temp_dir}.$defname.".torrent";
    $fromfile->save($newtorr);
    if(-f $newtorr){
        $torrent=$newtorr;
    }

	###################################
	# Upload torrent
	$r->form_new;
	# Form fields passed to upload script
	
	# Match IMDB URL
	my $match_imdb=qr/imdb.com\/title\/tt([0-9]*)/ms; 
        my $imdb=""; 
        if($descr_txt =~ $match_imdb){
                $imdb=$1; 
                $r->err("Found IMDB link: ".$imdb); 
        }
        
    $r->form_add('name', $name);
    $r->form_add('category', $category);
    $r->form_add('uploaderComments', '');
    $r->form_add('imagesFromURL[]', '');
    $r->form_add('addTags', '');
	$r->form_add('imdbID', $imdb);
	#$r->form_add('descr', $descr_txt);

	# Form files passed to upload script
	return 0 if(not $r->form_add_file('torrent', $torrent));
	return 0 if(not $r->form_add_file('nfo', $nfo));
    $r->form_add_file('cover', "");
    $r->form_add_file('images[]', "");

	# POStlg data to upload script
	$eh=$r->post("http://www.torrentleech.org/upload");
	return 0 if($eh==0);
    #$r->err($r->{curldat});

	my $torrentid=0;
	###################################
	# Search for already uploaded
	my $match_uploaded=qr/already uploaded/ms;
	my $uploaded_matches=$r->match('uploaded', $match_uploaded);
	if($uploaded_matches!=0){ $r->err('Torrent already uploaded, abortlg!'); return 0; }

	###################################
	# Search for torrent id
	my $match_torrentid=qr/<form action="\/download\/(.*?)\/(.*?)\.torrent" method="get">/ms;
	my $torrentid_matches=$r->match('torrent id', $match_torrentid);
	if($torrentid_matches==0){ $r->err('	Can not contlue without torrent ID, abortlg!'); return 0;}
	$torrentid=@$torrentid_matches[0];
	$r->err("	Torrent ID: $torrentid");
	
	###################################
	# Request torrent file
	my $eh=$r->get("http://www.torrentleech.org/download/".$torrentid."/some.torrent");
	return 0 if($eh==0);
	
	###################################
	# Check for bittorrent header
	my $file_type=$r->curl_get_type();
	if($file_type eq 0 or $file_type ne "application/x-bittorrent"){ $r->err("	Downloaded file is not bittorrent: ".$file_type); }

	###################################
	# Get infohash from downloaded file
	my $down_hash = $r->get_infohash_from_curl;
	if($down_hash eq 0){ $r->err('	Can not contlue without infohash, abortlg!'); return 0; }
	$r->err('	Downloaded file infohash: '.$down_hash);
	my $newtorr=$r->{curldat};

	$newtorr=$r->remove_hashcheck($config->{paths}->{upload_dir}, $newtorr);
	return 0 if($newtorr eq 0);

	###################################
	# Write torrent file
	my $torr_file=$config->{paths}->{watch2_dir}."[".uc($to_tracker)."]".$defname.".torrent";
	if($r->write_file('torrent', $torr_file, $newtorr)==0){ return 0; }

	my %retvals=(
		"id" => $torrentid,
		"hash" => $down_hash,
	);
	return \%retvals;

}
1;
