USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_FunctionUpdIsActive]    Script Date: 9/8/2014 4:53:05 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_FunctionUpdIsActive] 
	@FunctionID	    INT,		
	@IsActive		    BIT = 0,	
	@Language		    VARCHAR(20) = 'en-us',
	@LoginIP		    VARCHAR(30) = '',
	@ErrCode		    INT = 0 OUTPUT,
	@ErrMsg		    NVARCHAR(1000) = '' OUTPUT
AS

/*  
	 Created: 20140814@Florent
	 Task : Modify Function
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
*/
SET NOCOUNT ON
DECLARE
	 @startRun		DATETIME
	,@endRun		DATETIME
	,@duration		INT
	,@LogSPData		VARCHAR(5000)
	,@LogSPDataOld	VARCHAR(5000)
	
SET @startRun = getdate()

BEGIN	
	--check exist
	IF EXISTS (SELECT TOP 1 1 
				FROM dbo.LA_Function f WITH (NOLOCK) 
			  WHERE FunctionID = @FunctionID
			 )
     BEGIN	    
	   DECLARE  @FunctionName	    nvarchar(50),
			  @FunctionDesc	    nvarchar(50)='',
			  @ParentID		    int,	
			  @URL			    varchar(100),
			  @DisplayOrder	    int,
			  @FunctionKey		    nvarchar(50),
			  @Creator		    INT = 0
	   SELECT @FunctionName = f.FunctionName,
			  @FunctionDesc = f.FunctionDesc,
			  @ParentID = f.ParentID,	
			  @URL = f.URL,
			  @DisplayOrder = f.DisplayOrder,
			  @FunctionKey = f.FunctionKey,
			  @Creator = f.Creator		  
	   FROM dbo.LA_Function f WITH(NOLOCK)
	   WHERE FunctionID = @FunctionID

	   SELECT @LogSPDataOld =
		'<LA_FunctionUpdIsActive FunctionID="'+ coalesce(cast(FunctionID AS VARCHAR(10)),space(1)) + '" ' +
		'FunctionName="'+ coalesce(cast(FunctionName AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionKey="'+ coalesce(cast(FunctionKey AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionDesc="'+ coalesce(cast(FunctionDesc AS NVARCHAR(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(ParentID AS VARCHAR(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(ParentName as NVARCHAR(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(URL AS VARCHAR(100)),space(1)) + '" ' +
		'CreatedDate="'+ coalesce(cast(CreatedDate AS VARCHAR(50)),space(1)) + '" ' +
		'ModifiedDate="'+ coalesce(cast(ModifiedDate AS VARCHAR(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(DisplayOrder AS VARCHAR(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(Creator AS VARCHAR(10)),space(1)) + '" ' +
		'StatusID="'+ coalesce(cast(StatusID AS VARCHAR(20)),space(1)) + '" />' 
	   FROM  dbo.LA_Function WITH(NOLOCK)
	   WHERE FunctionID = @FunctionID

	    DECLARE @ParentName NVARCHAR(100) = 'None'	        
	    SELECT @ParentName = FunctionName FROM dbo.LA_Function WITH (NOLOCK) WHERE FunctionID=@ParentID
	    IF len(@FunctionDesc)=0
		  SELECT @FunctionDesc=@FunctionName

	    UPDATE dbo.LA_Function WITH (ROWLOCK, UPDLOCK) 
	    SET StatusID = @IsActive	    
	    WHERE FunctionID = @FunctionID

	    IF @@Error > 0
	    BEGIN
		    SELECT @ErrCode = 100
				, @ErrMsg = 'Failed to update function ' + convert(VARCHAR(10), @FunctionID)
		    RETURN
	    END

	    SELECT @LogSPData =
		'<LA_FunctionUpdIsActive FunctionID="'+ coalesce(cast(@FunctionID AS VARCHAR(10)),space(1)) + '" ' +
		'FunctionName="'+ coalesce(cast(@FunctionName AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionKey="'+ coalesce(cast(@FunctionKey AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionDesc="'+ coalesce(cast(@FunctionDesc AS NVARCHAR(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(@ParentID AS VARCHAR(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(@ParentName AS NVARCHAR(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(@URL AS VARCHAR(100)),space(1)) + '" ' +		
		'ModifiedDate="'+ coalesce(cast(GETDATE() AS VARCHAR(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(@DisplayOrder AS VARCHAR(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(@Creator AS VARCHAR(10)),space(1)) + '" ' +
		'StatusID="'+ coalesce(cast(@IsActive AS VARCHAR(20)),space(1)) + '" ' +
		'Language="'+ coalesce(cast(@Language AS VARCHAR(20)),space(1)) + '" ' +  
		'IP="'+ coalesce(cast(@LoginIP AS VARCHAR(50)),space(1)) + '" />'

		  SET @endRun = getdate()
		  SET @duration  = datediff (millisecond, @startRun, @endRun)

		  EXEC dbo.OA_WriteLog_UserLog_RunSP
			  @UserID = @Creator,
			  @CustID = 0,
			  @SPName ='LA_FunctionUpdIsActive',
			  @TrackingValue = @LogSPData,
			  @TrackingValue2 = @LogSPDataOld,
			  @duration = @duration
	END
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_FunctionUpdIsActive] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_FunctionUpdIsActive] TO bodbAdminNet 

