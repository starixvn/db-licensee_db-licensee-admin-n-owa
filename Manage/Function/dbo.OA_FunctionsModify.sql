ALTER PROCEDURE [dbo].[OA_FunctionsModify]
	 @FunctionID	INT							OUTPUT
	,@FunctionName	NVARCHAR(50)
	,@FunctionKey	NVARCHAR(50)
	,@FunctionDesc	NVARCHAR(50)	= ''
	,@ParentID		INT
	,@ParentName	NVARCHAR(100)	= ''
	,@URL			VARCHAR(100)	= ''
	,@CreatedDate	DATETIME
	,@ModifiedDate	DATETIME
	,@DisplayOrder	INT				= 10
	,@Creator		INT				= 0
	,@IsActive		BIT
	,@Language		VARCHAR(20)		= 'en-us'
	,@LoginIP		VARCHAR(30)		= ''
	,@ErrCode		INT				= 0			OUTPUT
	,@ErrMsg		NVARCHAR(1000)	= ''		OUTPUT
AS
/*  
 * Created: 20111128@Kos
 * Task : Creates/Updates a function
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON
DECLARE
	 @startRun		DATETIME
	,@endRun		DATETIME
	,@duration		INT
	,@LogSPData		VARCHAR(5000)
	,@LogSPDataOld	VARCHAR(5000)
	
SET @startRun = getdate()

IF EXISTS (SELECT 1 FROM dbo.OA_Functions WITH (NOLOCK) WHERE FunctionID = @FunctionID)
BEGIN -- Update existed function

SELECT @LogSPDataOld =
		'<OA_FunctionsModify FunctionID="'+ coalesce(cast(FunctionID AS VARCHAR(10)),space(1)) + '" ' +
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
		'IsActive="'+ coalesce(cast(IsActive AS VARCHAR(20)),space(1)) + '" />' 
	FROM  dbo.OA_Functions WITH(NOLOCK)
	WHERE FunctionID = @FunctionID

	UPDATE dbo.OA_Functions WITH (UPDLOCK, ROWLOCK)
	SET
		FunctionName = @FunctionName
		, FunctionKey = @FunctionKey
		, FunctionDesc = @FunctionDesc
		, ParentID = @ParentID
		, ParentName = @ParentName
		, URL = @URL
		, ModifiedDate = @ModifiedDate
		, DisplayOrder = @DisplayOrder
		, Creator = @Creator
		, IsActive = @IsActive
	WHERE
		FunctionID = @FunctionID
			
	IF @@Error > 0
	BEGIN
		SELECT @ErrCode = 100
			 , @ErrMsg = 'Failed to update function ' + convert(VARCHAR(10), @FunctionID)
		RETURN
	END

END
ELSE -- Create new function
BEGIN

	INSERT
		dbo.OA_Functions
		(
		FunctionID
	  , FunctionName
	  , FunctionKey
	  , FunctionDesc
	  , ParentID
	  , ParentName
	  , URL
	  , CreatedDate
	  , ModifiedDate
	  , DisplayOrder
	  , Creator
	  , IsActive
		)
	VALUES
		(
		@FunctionID
		, @FunctionName
		, @FunctionKey
		, @FunctionDesc
		, @ParentID
		, @ParentName
		, @URL
		, @CreatedDate
		, @ModifiedDate
		, @DisplayOrder
		, @Creator
		, @IsActive
		)
	
	SET @FunctionID = SCOPE_IDENTITY()
	
	IF @@Error > 0
	BEGIN
		SELECT @ErrCode = 101
			 , @ErrMsg = 'Failed to insert function ' + convert(VARCHAR(10), @FunctionID)
		RETURN
	END
END


SELECT @LogSPData =
		'<OA_FunctionsModify FunctionID="'+ coalesce(cast(@FunctionID AS VARCHAR(10)),space(1)) + '" ' +
		'FunctionName="'+ coalesce(cast(@FunctionName AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionKey="'+ coalesce(cast(@FunctionKey AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionDesc="'+ coalesce(cast(@FunctionDesc AS NVARCHAR(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(@ParentID AS VARCHAR(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(@ParentName AS NVARCHAR(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(@URL AS VARCHAR(100)),space(1)) + '" ' +
		'CreatedDate="'+ coalesce(cast(@CreatedDate AS VARCHAR(50)),space(1)) + '" ' +
		'ModifiedDate="'+ coalesce(cast(@ModifiedDate AS VARCHAR(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(@DisplayOrder AS VARCHAR(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(@Creator AS VARCHAR(10)),space(1)) + '" ' +
		'IsActive="'+ coalesce(cast(@IsActive AS VARCHAR(20)),space(1)) + '" ' +
		'Language="'+ coalesce(cast(@Language AS VARCHAR(20)),space(1)) + '" ' +  
		'IP="'+ coalesce(cast(@LoginIP AS VARCHAR(50)),space(1)) + '" />'

SET @endRun = getdate()
SET @duration  = datediff (millisecond, @startRun, @endRun)

EXEC dbo.OA_WriteLog_UserLog_RunSP
	@UserID = @Creator,
	@CustID = 0,
	@SPName ='OA_FunctionsModify',
	@TrackingValue = @LogSPData,
	@TrackingValue2 = @LogSPDataOld,
	@duration = @duration
	
GO
GRANT EXECUTE ON [dbo].[OA_FunctionsModify] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionsModify] TO [vnteam]  	