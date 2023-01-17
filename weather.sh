# !/bin/bash
# Timothy Salazar
# 2022-9-14
# Queries the National Weather Service API to retrieve the day's forecast:
#       https://www.weather.gov/documentation/services-web-api
# This is a 100% free service, but it's only available in the US.

######################
# Command line parsing
######################
RAW_DATA=0
DETAILED_FORECAST=0
HELP=0
QUIET=0
DEBUG=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --latitude) LATITUDE="$2"; shift ;;
        --longitude) LONGITUDE="$2"; shift ;;
        -r|--raw) RAW_DATA=1 ;;
        -d|--detailed-forecast) DETAILED_FORECAST=1 ;;
        -h|--help) HELP=1 ;;
        -q|--quiet) QUIET=0 ;;
        --debug) DEBUG=1 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

###################
# Display help text
###################
if [ $HELP -eq 1 ]; then
    echo "This script queries the National Weather Service API to retrieve the day's forecast:
        https://www.weather.gov/documentation/services-web-api
    While this is a 100% free service, it's only available in the US. 
    In order for this to function, you'll need to set the environment variables LATITUDE and LONGITUDE
    to reflect your location. 
    Alternately, you can specify your latitude and longitude with the --latitude and --longitude arguments
        --latitude : specify the latitude for which you would like forecast data
        --longitude : specify the longitude for which you would like forecast data
        --raw / -r : returns all the data returned by the API without parsing
        --detailed-forecast / -d : the 'forecast' field will contain the detailed forecast instead of the short forecast
        --quiet /-q : suppresses warning message
        --help / -h : displays this help text
    "
    exit 0
fi

#############################
# Check environment variables
#############################
# Check if latitude is set
NO_LAT=0
NO_LONG=0
if [[ -z "${LATITUDE}" ]]; then
    NO_LAT=1
    LATITUDE=38.0612
fi
# Check if longitude is set
if [[ -z "${LONGITUDE}" ]]; then
    NO_LONG=1
    LONGITUDE=-105.0939
fi
# Print warning 
if [[ NO_LAT -eq 1 || NO_LONG -eq 1 ]]; then
    WARNING="WARNING:"
    if [[ NO_LAT -eq 1 ]]; then
        WARNING="$WARNING \nLATITUDE not provided."
    fi
    if [[ NO_LONG -eq 1 ]]; then
        WARNING="$WARNING \nLONGITUDE not provided."
    fi
    WARNING="
    ################################################################################
    \n$WARNING 
    \nEither set the LATITUDE and LONGITUDE environment variables, or provide values
    \nfor latitude and longitude using the --latitude and --longitude command line 
    \narguments if you want the forecast for a specific location.
    \n\nExample lat/long values are being set for demo purposes."
fi

##############
# Get JSON
##############

retrieve_JSON () {
    # This function should be called with a url as an argument.
    # It makes a call to the URL given (presumably a valid URL for the 
    # NWS API) and does some quick sanity checks to see if it looks roughly
    # correct. 
    # The data returned by the API will be saved to the JSON variable. 
    URL=$1
    if [ $DEBUG -eq 1 ]; then
        JSON=$(curl --fail-with-body $URL)
    else
        JSON=$(curl -s --fail-with-body $URL)
    fi
    # We used the --fail-with-body flag when we curled URL. If the HTTP 
    # response code received from the API was 400 or greater, curl will return 
    # an exit code of 22. 
    # The body returned by the API (which might include the reason it failed) is 
    # still contained in $JSON
    if [ $? -gt 0 ]; then
        echo "Error retrieving data from API:
        \nURL used: 
        \n\t$URL
        \nAPI returned the following:"
        echo "$JSON"
        exit 1
    fi

    # Here we're doing a quick and dirty check to see if the JSON document 
    # has the structure we're expecting
    HAS_PROPERTIES=$(echo $JSON | jq '. | has("properties")')
    HAS_STATUS=$(echo $JSON | jq '. | has("status")')
    if [ "$HAS_PROPERTIES" != "true" ]; then
        echo "Error: could not parse JSON returned by the API"
        echo "JSON received:"
        echo $JSON
        if [ "$HAS_STATUS" = "true" ]; then
            STATUS=$(echo $JSON | jq '.status')
            echo "Status code: $STATUS"
        fi
        exit 1
    fi

    # This probably doesn't matter, but I like to explicitly sleep after I make 
    # API requests, even though it shouldn't matter here (since we're just
    # making two requests)
    sleep .2
}

###############
# Query the API
###############
BASE_URL='https://api.weather.gov'
# Because of how the API is set up, we need to get a grid point corresponding to
# our location first, and then we can retrieve a forecast
POINT_URL="$BASE_URL/points/$LATITUDE,$LONGITUDE"
retrieve_JSON $POINT_URL

# Now we're going to query the API for the forecast 
FORECAST_URL=$(echo $JSON | jq -r '.properties | .forecast')
retrieve_JSON $FORECAST_URL
WEEK_FORECAST=$JSON
# WEEK_FORECAST=$(curl -s $FORECAST_URL)

if [ $RAW_DATA -eq 1 ]; then
    echo $WEEK_FORECAST | jq

else 
    FILTER='.properties | 
    .periods | 
    .[] 
    | '
    SCHEMA='{
        name: .name,  
        temperature: 
        (
            (
                (.temperature|tostring+"º")+.temperatureUnit
            )+ 
            (
                if .temperatureTrend then (" and "+.temperatureTrend) else "" end
                
            )
        ), 
        wind: ((.windSpeed+" ")+.windDirection)'
    if [ $DETAILED_FORECAST -eq 1 ]; then
        SCHEMA="$SCHEMA,
        forecast: .detailedForecast
        }"
    else
        SCHEMA="$SCHEMA,
        forecast: .shortForecast
        }"
    fi
    echo $WEEK_FORECAST | jq "$FILTER$SCHEMA"
fi

if [ $QUIET -eq 0 ]; then
    echo $WARNING
fi