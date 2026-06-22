var uiEdited = false;
var detectorMoving = false; 
var moveEnabled = false;
var detectorOffset = [ 0, 0 ]; 

var windowWidth = 0; 
var windowHeight = 0; 

var safezone = 0; 

window.addEventListener('message', function(event) {
    var item = event.data; 
    var type = event.data._type; 
    switch ( type ) {
        // System events 
        case "loadUiSettings":
            loadUiSettings( item.data, true );
            break;
        case "setUiDefaults":
            loadUiSettings( item.data, false ); 
            break; 
        default:
            break;
    }

    if (event.data.action == 'open') {
        $('#detector').fadeIn("slow");
        $('.detectorImg').attr("src", "images/DefaultState.png");
        $(".screeninfo").show();
        setUiHasBeenEdited( false ); 
    } else if (event.data.action == 'close') {
        $('#detector').fadeOut("slow");
        $(".screeninfo").hide();
    } else if (event.data.action == 'startup') {
        $('#detector').fadeIn("slow");


    }
    

    if (event.data.action == "detect") {
        $('.detectorImg').attr("src", event.data.signal);
    }

    if (event.data.action == "moveMode") {
        moveEnabled = event.data.enabled === true;
        detectorMoving = false;
        $('#detector').toggleClass('moving', moveEnabled);
    }
    
    if (event.data.speed !== undefined) {
        $("#speed").html(event.data.speed);
    }

    if (event.data.units !== undefined) {
        $('#units').text(event.data.units);
    }
});




$(document).on("pointermove mousemove", function(event) {
    if (!detectorMoving) {
        return;
    }

    let sourceEvent = event.originalEvent || event;
    let x = sourceEvent.clientX;
    let y = sourceEvent.clientY;

    event.preventDefault();
    calculatePos($("#detector"), x, y, windowWidth, windowHeight, detectorOffset, safezone);
});

 $( window ).resize( function() {
	windowWidth = $( this ).width(); 
	windowHeight = $( this ).height(); 
} )

 $( document ).ready( function() {
	windowWidth = $( window ).width(); 
	windowHeight = $( window ).height();
});

$(document).keyup(function(e) {
    if (e.key === "Escape") {
        $.post('https://' + GetParentResourceName() + '/close');
        sendSaveData(); 
    };
});



$(document).on("pointerdown mousedown", "#detector", function(event) {
	if (!moveEnabled) {
		return;
	}

    let sourceEvent = event.originalEvent || event;

	event.preventDefault();
	detectorMoving = true; 

	let offset = $( "#detector").offset();

	detectorOffset = getOffset(offset, sourceEvent.clientX, sourceEvent.clientY);
});

$(document).on("pointerup mouseup pointercancel", function() {
	detectorMoving = false; 
});

$(document).on("dragstart selectstart", "#detector, #detector *", function(event) {
    event.preventDefault();
});

function Mute() {
    $.post('https://' + GetParentResourceName() + '/mute');
};

function getOffset( offset, x, y )
{

	return [
		offset.left - x, 
		offset.top - y
	]
}



function updatePosition( ele, left, top )
{
	ele.css( "left", left + "%" );
	ele.css( "top", top + "%" );
}

function calculatePos( ele, x, y, w, h, offset, safezone )
{
    let eleWidth = ( 1.0 );
	let eleHeight = ( 1.0 );

	let maxWidth = w - eleWidth;
	let maxHeight = h - eleHeight; 

	let left = clamp( x + offset[0], 0 + safezone, maxWidth - safezone );
	let top = clamp( y + offset[1], 0 + safezone, maxHeight - safezone );

	let leftPos = ( left / w ) * 100; 
	let topPos = ( top / h ) * 100; 


	// Lock pos check 


	updatePosition( ele, leftPos, topPos );
	setUiHasBeenEdited( true ); 
}

function clamp( num, min, max )
{
	return num < min ? min : num > max ? max : num;
}



// This function is used to send data back through to the LUA side 
function sendData( name, data ) {
	$.post( "https://" + GetParentResourceName() + "/" + name, JSON.stringify( data ), function( datab ) {
    
	} );
}

// Sets the ui edited variable to the given state, this is used in the UI save system 
function setUiHasBeenEdited( state )
{
	uiEdited = state; 
}

// Returns if the UI has been edited
function hasUiBeenEdited()
{
	return uiEdited;
}


// Gathers the UI data and sends it to the Lua side
function sendSaveData()
{
    moveEnabled = false;
    detectorMoving = false;
    $('#detector').removeClass('moving');

    let data = {
        detector: {
            left: $("#detector").css("left"),
            top: $("#detector").css("top")
        }
    }
		// Send the data
    sendData( "saveUiData", data );
}

// Loads the UI settings 
function loadUiSettings( data, isSave )
{
	if (!data || !data.detector) {
		data = {
			detector: {
				left: "2%",
				top: "6%"
			}
		};
	}

	// Iterate through "remote", "radar" and "plateReader"
	for ( let setting of [ "detector"] ) 
	{
		let ele = $("#" + setting);

		if ( isSave ) {
			// Iterate through the settings
			for ( let i of [ "left", "top" ] )
			{
				// Update the position of the current element 
				$("#detector").css( i, data[setting][i] );
			}
		
        } else {
			switch ( setting ) {
				case "detector":
					ele.css( "left", data.detector.left );
					ele.css( "top", data.detector.top );
					break;
				
				default:
					break;
			}
		}
	}


}
