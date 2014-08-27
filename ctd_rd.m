function [ctd,varlabel,names,sensors]=ctd_rd(cnv_file,FMT);
% CTD_RD Reads the SeaBird ASCII .CNV file format
%
%  Usage:   CTD=ctd_rd(cnv_file);
%
%     Input:  cnv_file = name of .CNV file  (e.g. 'cast002.cnv')
%
%     Output: CTD - a data structure containing the CTD data and header info.
%
%  There are various formats possible for time/location information.
%  Some of these can be handled with an optional second input parameter:
%           CTD=ctd_rd(cnv_file,FORMAT)
%
%  where FORMAT = 'NMEA'  for SEASAVE output with GPS included through deckbox
%
%                          * System UpLoad Time = Oct 10 1999  18:20:32
%                          * NMEA Latitude = 48 36.69 N
%                          * NMEA Longitude = 123 13.07 W
%                          * NMEA UTC (Time) = Oct 10 1999  18:20:32
%
%                 'IR'    for an internally recording mode with a hand-typed
%                         header in this form:
%                         
%                          ** Latitude = 49 21.092 N
%                          ** Longitude = 121 49.028 W
%                          ** PST (Time) =Nov 23 2000 07:45
%
%                         will also work with SEASAVE output if no
%                         GPS NMEA string available.
%                         (default mode)
%
%                         If no '** Time' line gets it from System Upload Time
%
%                 'RP'    Ignore any header data but decode System Upload Time for
%                         the year, and the 'cast' line (DH command) for time -
%                         good for IR mode when to-yo-ing or otherwise too lazy
%                         to create proper headers.
%
%                 'LAB'   for a mode with no NMEA or header data (i.e. lab
%                         testing)
%
%  Add more lat,lon and date string handling if your .CNV files are different.
%

%  4-8-98  Rich Signell (rsignell@usgs.gov)  
%     incorporates ideas from code by Derek Fong & Peter Brickley
%  19-9-99 R. pawlowicz (ric@ocgy.ubc.ca)
%      - added a lot more decoding plus the idea of a data stucture for output
%  12-6-00 Changes variable names slightly.
%  19-2-02 dms as well as dmm.mm formats
%  20-5-11 modified by Rowan Fox (ro1@uvic.ca), adding in model #, temp
%  sensor SN # & cond sensor SN
%  16-5-12 can now read new-format cnv files with xml info


if nargin==1,
 FMT='IR';
end;

ctd.name='ctd';
ctd.station='';

% Open the .cnv file as read-only text

if isempty(findstr(lower(cnv_file),'.cnv')),
  cnv_file=[cnv_file '.cnv'];
end;
  
fid=fopen(cnv_file,'r');

% Read the header.
lat=[];
lon=[];
gtime=NaN(1,6);
tzone='unknown';
% Stop at line that starts with '*END*'

str='*START*';
while (~strncmp(str,'*END*',5));
  
  str=fgetl(fid);

   switch FMT
     case 'NMEA'
	 if (strncmp(str,'* NMEA Lat',10))
            lat=get_lat(str);
	 elseif (strncmp(str,'* NMEA Lon',10))
            lon=get_lon(str);
	 elseif (strncmp(str,'* NMEA UTC',10))
           gtime=get_timestamp(str);
	   tzone='UTC';
	end;

     case 'IR',

	 if any(findstr(str,'Latitude')) | any(findstr(str,'Lat'))
            lat=get_lat(str);
	 elseif any(findstr(str,'Longitude')) | any(findstr(str,'Long'))
            lon=get_lon(str);
	    
   %    Read the  TIME string.  This may vary with CTD setup. Will need
   %      ** xxxxxxxxxxTimexxxx = 21 Dec 2005 hh:mm:ss
   %     where timezone may also be in there somewhere.
   
        elseif strncmp(str,'**',2) & any(findstr(str,'Time')),
           gtime=get_timestamp(str);
	   tzone='unknown';
	   if any(findstr(str,'PST')),
	     tzone='PST';
	   elseif any(findstr(str,'PDT')),
	     tzone='PDT';
	   elseif any(findstr(str,'UTC')),
	     tzone='UTC';
	   elseif any(findstr(str,'EST')),
	     tzone='EST';
	   elseif any(findstr(str,'EDT')),
	     tzone='EDT';
	   end;  
   % The default - get a time from the 'upload' string (usually the other time
   % strings are later in the file so they will overwrite this, if they exist).	
	elseif (strncmp(str,'* System UpLoad',15)),
           tzone='unknown';
           gtime=get_timestamp(str);
	end;	

       case 'LAB',  	
       
  
        if (strncmp(str,'* System UpLoad',15)),
           tzone='unknown';
           gtime=get_timestamp(str);
	end;
	
      case 'RP',  
      	

	if (strncmp(str,'* System UpLoad',15))
           is=findstr(str,'=');
	%EXTRACT THE UPLOAD YEAR FOR CAST START TIME Roger 2003sep04
           upyearstr=str(is+9:is+12);
	end;

   
   %-------------------------------------------------------------------
	% READ CAST START TIME, SAMPLE RATE, COMPUTE mtime Roger 2003sep04
	% * cast 0  06/23  17:38:06   samples 0 to 1334 sample rate = 1 scan every 0.5 seconds
	if (strncmp(str,'* cast ',7))
           %Find slash
           indslash=find(str=='/');
           indcolon=find(str==':');

	   if length(indslash)==1 & length(indcolon)>=2
             datstr=[upyearstr ' '...
                     str(indslash-2:indslash-1) ' ' ...
                     str(indslash+1:indslash+2) ' ' ...
                     str(indcolon(1)-2:indcolon(1)-1) ' '...
                     str(indcolon(1)+1:indcolon(2)-1) ' '...
                     str(indcolon(2)+1:indcolon(2)+2)];
             mtime=datenum(str2num(datstr));
	     gtime=datevec(mtime);
             fprintf('Date from CAST START TIME in timezone of SBE clock\n');
	   else
              error('ERROR: CAST START TIME: str does not have expected form')
	   end;

	end

   %
      otherwise,
	error('Unrecognized format specifier');
    end;
  	
%-----------------------------
%
% Read the station name from a comment line
%
     if (strncmp(lower(str),'** station',10)),
        ctd.station=fliplr(deblank(fliplr(deblank(str(min(findstr(str,':'))+2:end)))));
%-----------------------------
%
% Read the ctd model from a comment line
%
     elseif (strncmp(str,'* Sea-Bird',10)),
        ctd.model=str(findstr(str,'Sea-Bird SBE ')+13:findstr(str,' Data File')-1);
%-----------------------------
%
% Read the ctd temperature sensor SN from a comment line
%
     elseif (strncmp(str,'* Temperature SN = ',19)),
        ctd.tempsn=str(findstr(str,'* Temperature SN = ')+19:end);
%-----------------------------
%
% Read the ctd conductivity sensor SN from a comment line
%
     elseif (strncmp(str,'* Conductivity SN = ',20)),
        ctd.condsn=str(findstr(str,'* Conductivity SN = ')+20:end);
        
%-----------------------------
%
% Read the depth from a comment line
%
     elseif (strncmp(lower(str),'** depth',8)),
        idelim=findstr(str,':');
        ctd.depth=sscanf(str(idelim+1:end),'%f');
	if isempty(ctd.depth), ctd.depth=NaN; end;
	% Units?
	strrem=str(idelim+1:end);strrem(strrem>=48 & strrem<=57)=' ';
	if any(findstr(str(idelim+1:end),' m')),
	   % OK
	elseif any(findstr(str(idelim+1:end),' ft')) ,
	   ctd.depth=ctd.depth*0.3048;
	end;    

%------------------------------
%
% Get sampling interval
%
     elseif (strncmp(str,'# interval',10)),
        ctd.samp_interval=sscanf(str(findstr(str,':')+1:end),'%f');

%------------------------------
%
% Get start time  
%
     elseif (strncmp(str,'# start_time',12)),
        ctd.start_time=str(15:end)
        str(15:35)
        ctd.start_mtime=datenum(str(15:35),' mmm dd yyyy HH:MM:SS');
	
%------------------------------
%
%    Read the variable names & units into a cell array
%
     elseif (strncmp(str,'# name',6))  
        var=sscanf(str(7:10),'%d',1);
	var=var+1;
        ctd.varlabel{var}=str(findstr(str,'=')+2:min([findstr(str,':')-1 ...
                              findstr(str,'/')-1 findstr(str,'-')-1]));
%------------------------------
%
%    Read the sensor names into a cell array
%
     elseif (strncmp(str,'# sensor',8))  
        sens=sscanf(str(10:11),'%d',1);
        sensors{sens+1}=str;
%------------------------------
%
%    Read the sensor ranges into a cell array
%
     elseif (strncmp(str,'# span',6))  
        sens=sscanf(str(8:9),'%d',1);
        ctd.spans{sens+1}=sscanf(str(findstr(str,'=')+1:end),'%f,%f');
%
%  pick up bad flag value
     elseif (strncmp(str,'# bad_flag',10))  
        isub=13:length(str);
        bad_flag=sscanf(str(isub),'%g',1);
     end
end
%==============================================


%  Done reading header.  Now read the data!

nvars=var;  %number of variables

% Read the data into one big matrix

data=fscanf(fid,'%f',[nvars inf]).';
fclose(fid);


% Flag bad values with NaN

data(data==bad_flag)=NaN;

if exist('sensors'), ctd.sensors=char(sensors); end;

ctd.latitude=lat;
ctd.longitude=lon;
ctd.gtime=gtime;
ctd.mtime=datenum(gtime(1),gtime(2),gtime(3),gtime(4),gtime(5),gtime(6));
ctd.tzone=tzone;

if strcmp(FMT,'RP'),
  ctd.mtimescan=[0:size(data,1)-1]*ctd.samp_interval/86400+mtime;
end;  

labeldel=[];
for k=1:length(ctd.varlabel),
  if diff(ctd.spans{k})~=0,
    eval(['ctd.' ctd.varlabel{k} '=data(:,k);']);
  else
    labeldel=[labeldel k];
  end;
end;
ctd.varlabel(labeldel)=[];
ctd.spans(labeldel)=[];
 
return

%---------------------------------------------------
function lon=get_lon(str);
% decodes latitude from input string

% Get delimiter - '=' or ':'
is=findstr(str,'=');
if isempty(is), is=findstr(str,':'); end;


isub=is+1:length(str);
dm=sscanf(str(isub),'%f');

% E or W
if(findstr(str(isub),'E')); sigl=1; else sigl=-1; end;

% dd.ddd or dd mm.mmm or dd mm ss formats
switch (length(dm)),
case 1,
   lon=sigl*dm;
case 2,   	
   lon=sigl*(dm(1)+dm(2)/60);
case 3,  
   lon=sigl*(dm(1)+dm(2)/60+dm(3)/3600);
otherwise,
   lon=NaN;
   disp(['Can''t scan string ->' str '<- for longitude']);    
end
 
return;

%---------------------------------------------------
function lat=get_lat(str);
% decodes latitude from input string

% Get delimiter - '=' or ':'
is=findstr(str,'=');
if isempty(is), is=findstr(str,':'); end;


isub=is+1:length(str);
dm=sscanf(str(isub),'%f');

% N or S
if(findstr(str(isub),'N')); sigl=1; else sigl=-1; end;

% dd.ddd or dd mm.mmm or dd mm ss formats
switch (length(dm)),
case 1,
   lat=sigl*dm;
case 2,   	
   lat=sigl*(dm(1)+dm(2)/60);
case 3,  
   lat=sigl*(dm(1)+dm(2)/60+dm(3)/3600);
otherwise,
   lat=NaN;
   disp(['Can''t scan string ->' str '<- for longitude']);    
end
 
return;
%--------------------------------------------------
function gtime=get_timestamp(str);
% Decodes time string

% Time to right of '='
idelim=findstr(str,'=');
if any(idelim),
   str=str(idelim+1:end);
else   % try a colon delimiter
 idelim=findstr(str,':');
 if any(idelim),
    str=str(idelim(1)+1:end);
 end;
end;
     
% is there hh:mm:ss in there?
is=findstr(str,':');
if any(is),
  isub=is(1)-2:length(str);
  
  % Date in   Dec 21 2005 format
  nbl=find(str(1:is(1)-3)~=' ');
  datstr=str(min(nbl):max(nbl));
  ibl=findstr(datstr,' ');
  if length(ibl)==2,
    % Write into 21-Dec-2001 format which matlab can decode
    datstr=[datstr(ibl(1)+1:ibl(2)-1) '-' datstr(1:ibl(1)-1) '-' datstr(ibl(2)+1:end)];
    if ibl(2)-ibl(1)==2,
      datstr=['0' datstr];
    end; 
    gtime=datevec(datstr);
    % Add hh:mm:ss
    if length(is)==1,
      gtime([4:5])=sscanf(str(isub),'%d:%2d');
    elseif length(is)==2,
      gtime([4:6])=sscanf(str(isub),'%d:%2d:%2d');
    else
      disp(['Can''t scan string ->' str '<- for time of day']);    
      gtime=[0 0 0 0 0 0];
    end; 
  else
    disp(['Can''t scan string ->' str '<- for day of year']);    
   gtime=[0 0 0 0 0 0];
  end; 
else
    disp(['Can''t scan string ->' str '<- for time of day']);    
   gtime=[0 0 0 0 0 0];
end; 



