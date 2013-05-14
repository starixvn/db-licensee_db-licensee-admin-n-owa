ALTER PROCEDURE [dbo].[OA_MenusModify]
	 @MenuID		INT							OUTPUT
	,@MenuName		NVARCHAR(100)
	,@MenuDesc		NVARCHAR(100)	= ''
	,@ParentID		INT
	,@ParentName	NVARCHAR(100)	= ''
	,@URL			VARCHAR(100)	= ''
	,@CreatedDate	DATETIME
	,@ModifiedDate	DATETIME
	,@DisplayOrder	INT				= 10
	,@Creator		INT				= 0
	,@IsActive		BIT
	,@FunctionID	INT
	,@Policy		INT
	,@Language		VARCHAR(20)		= 'en-us'
	,@LoginIP		VARCHAR(30)		= ''
	,@ErrCode		INT				= 0			OUTPUT
	,@ErrMsg		NVARCHAR(1000)	= ''		OUTPUT
AS
/*  
 * Created: 20111017@Lewis
 * Task : Creates/Updates a menu
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

IF EXISTS (SELECT 1 FROM dbo.OA_Menus WITH (NOLOCK) WHERE MenuID = @MenuID)
BEGIN -- Update existed menu

SELECT @LogSPDataOld =
		'<OA_MenusModify MenuID="'+ coalesce(cast(MenuID AS VARCHAR(10)),space(1)) + '" ' +
		'MenuName="'+ coalesce(cast(MenuName as nvarchar(50)),space(1)) + '" ' +
		'MenuDesc="'+ coalesce(cast(MenuDesc as nvarchar(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(ParentID as varchar(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(ParentName as nvarchar(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(URL as varchar(100)),space(1)) + '" ' +
		'CreatedDate="'+ coalesce(cast(CreatedDate as varchar(50)),space(1)) + '" ' +
		'ModifiedDate="'+ coalesce(cast(ModifiedDate as varchar(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(DisplayOrder as varchar(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(Creator as varchar(10)),space(1)) + '" ' +
		'IsActive="'+ coalesce(cast(IsActive as varchar(20)),space(1)) + '" ' +
		'FunctionID="'+ coalesce(cast(FunctionID as varchar(10)),space(1)) + '" ' +
		'Policy="'+ coalesce(cast(Policy as varchar(10)),space(1)) + '" />' 
	FROM  dbo.OA_Menus WITH(NOLOCK)
	WHERE MenuID = @MenuID

	UPDATE dbo.OA_Menus WITH (UPDLOCK, ROWLOCK)
	SET
		MenuName = @MenuName
		, MenuDesc = @MenuDesc
		, ParentID = @ParentID
		, ParentName = @ParentName
		, URL = @URL
		, ModifiedDate = @ModifiedDate
		, DisplayOrder = @DisplayOrder
		, Creator = @Creator
		, IsActive = @IsActive
		, FunctionID = @FunctionID
		, Policy = @Policy
	WHERE
		MenuID = @MenuID
			
	IF @@Error > 0
	BEGIN
		SELECT @ErrCode = 100
			 , @ErrMsg = 'Failed to update menu ' + convert(VARCHAR(10), @MenuID)
		RETURN
	END

END
ELSE -- Create new menu
BEGIN

	INSERT
		dbo.OA_Menus
		(
		MenuID
	  , MenuName
	  , MenuDesc
	  , ParentID
	  , ParentName
	  , URL
	  , CreatedDate
	  , ModifiedDate
	  , DisplayOrder
	  , Creator
	  , IsActive
	  , FunctionID
	  , Policy
		)
	VALUES
		(
		@MenuID
		, @MenuName
		, @MenuDesc
		, @ParentID
		, @ParentName
		, @URL
		, @CreatedDate
		, @ModifiedDate
		, @DisplayOrder
		, @Creator
		, @IsActive
		, @FunctionID
		, @Policy
		)
	
	SET @MenuID = SCOPE_IDENTITY()
	
	IF @@Error > 0
	BEGIN
		SELECT @ErrCode = 101
			 , @ErrMsg = 'Failed to insert menu ' + convert(VARCHAR(10), @MenuID)
		RETURN
	END
END


SELECT @LogSPData =
		'<OA_MenusModify MenuID="'+ coalesce(cast(@MenuID AS VARCHAR(10)),space(1)) + '" ' +
		'MenuName="'+ coalesce(cast(@MenuName as nvarchar(50)),space(1)) + '" ' +
		'MenuDesc="'+ coalesce(cast(@MenuDesc as nvarchar(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(@ParentID as varchar(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(@ParentName as nvarchar(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(@URL as varchar(100)),space(1)) + '" ' +
		'CreatedDate="'+ coalesce(cast(@CreatedDate as varchar(50)),space(1)) + '" ' +
		'ModifiedDate="'+ coalesce(cast(@ModifiedDate as varchar(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(@DisplayOrder as varchar(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(@Creator as varchar(10)),space(1)) + '" ' +
		'IsActive="'+ coalesce(cast(@IsActive as varchar(20)),space(1)) + '" ' +
		'FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +
		'Policy="'+ coalesce(cast(@Policy as varchar(10)),space(1)) + '" ' +
		'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
		'IP="'+ coalesce(cast(@LoginIP as varchar(50)),space(1)) + '" />'

SET @endRun = getdate()
SET @duration  = datediff (millisecond, @startRun, @endRun)

EXEC dbo.OA_WriteLog_UserLog_RunSP
	@UserID = @Creator,
	@CustID = 0,
	@SPName ='OA_MenusModify',
	@TrackingValue = @LogSPData,
	@TrackingValue2 = @LogSPDataOld,
	@duration = @duration
	

GO
GRANT EXECUTE ON [dbo].[OA_MenusModify] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_MenusModify] TO [vnteam]
  