/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionIns] 
	@FunctionID		INT OUTPUT,
	@FunctionName	nvarchar(50),
	@FunctionDesc	nvarchar(50) = '',
	@GroupIDs		Varchar(5500) = '', -- '1,2,3'
	@ParentID		int,	
	@URL			varchar(100),
	@DisplayOrder	int,
	@Creator		int,
	@IsActive		bit = 0,
	@FunctionKey	nvarchar(50),
	@Language		VARCHAR(20) = 'en-us',
	@LoginIP		VARCHAR(30) = '',
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			NVARCHAR(1000) = '' OUTPUT
AS

/*  
	 Created: 20140814@Florent
	 Task : Create new Function
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20150904@Bravo: add default function permission
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
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
	IF NOT EXISTS (SELECT TOP 1 1 
			 FROM dbo.LA_Function f WITH (NOLOCK) 
			 WHERE f.FunctionKey=@FunctionKey
			 )
     BEGIN	    
	    DECLARE @ParentName NVARCHAR(100) = 'None'	        
	    SELECT @ParentName=FunctionName FROM dbo.LA_Function WITH (NOLOCK) WHERE FunctionID=@ParentID
	    IF len(@FunctionDesc)=0
		  SELECT @FunctionDesc=@FunctionName

	    INSERT INTO dbo.LA_Function WITH(ROWLOCK) (FunctionName,FunctionDesc,ParentID,ParentName,URL,CreatedDate,ModifiedDate,DisplayOrder,Creator,StatusID,FunctionKey)
	    VALUES(@FunctionName,@FunctionDesc,@ParentID,@ParentName,@URL,GETDATE(),GETDATE(),@DisplayOrder,@Creator,@IsActive,@FunctionKey)

	    SELECT @FunctionID = @@IDENTITY
	    IF @@ERROR <> 0 --rollback
		  BEGIN
			 SELECT @ErrCode = 101
			 , @ErrMsg = 'Failed to insert function ' + convert(VARCHAR(10), @FunctionID)
			  DELETE dbo.LA_Function WITH(ROWLOCK) WHERE FunctionID=@FunctionID
			  RETURN
		  END 
		
		--Add to Group Function
		INSERT INTO dbo.LA_GroupFunction WITH (ROWLOCK) (GroupID,FunctionID)
		SELECT value,@FunctionID
		FROM STRING_SPLIT(@GroupIDs,',')
		
		-- Add to User Function
		INSERT INTO dbo.LA_UserFunction
		VALUES(@Creator, @FunctionID, GETDATE(), @Creator, 1)
		
		IF @@ERROR <> 0 --rollback
		BEGIN
			 SELECT @ErrCode = 101
			 , @ErrMsg = 'Failed to insert Function ' + convert(VARCHAR(10), @FunctionID) + ' to Group '+ convert(VARCHAR(10), @GroupIDs)
			  DELETE dbo.LA_Function WITH(ROWLOCK) WHERE FunctionID=@FunctionID
			  DELETE dbo.LA_GroupFunction WITH(ROWLOCK) WHERE FunctionID=@FunctionID
			  DELETE dbo.LA_UserFunction WITH(ROWLOCK) WHERE FunctionID=@FunctionID
			  RETURN
		END 
	END	
	SELECT @FunctionID	
	
	--Write Log	
	SELECT @LogSPData =
		'<LA_FunctionIns FunctionID="'+ coalesce(cast(@FunctionID AS VARCHAR(10)),space(1)) + '" ' +
		'FunctionName="'+ coalesce(cast(@FunctionName AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionKey="'+ coalesce(cast(@FunctionKey AS NVARCHAR(50)),space(1)) + '" ' +
		'FunctionDesc="'+ coalesce(cast(@FunctionDesc AS NVARCHAR(50)),space(1)) + '" ' +
		'ParentID="'+ coalesce(cast(@ParentID AS VARCHAR(10)),space(1)) + '" ' +
		'ParentName="'+ coalesce(cast(@ParentName AS NVARCHAR(50)),space(1)) + '" ' +
		'URL="'+ coalesce(cast(@URL AS VARCHAR(100)),space(1)) + '" ' +
		'CreatedDate="'+ coalesce(cast(GETDATE() AS VARCHAR(50)),space(1)) + '" ' +
		'ModifiedDate="'+ coalesce(cast(GETDATE() AS VARCHAR(50)),space(1)) + '" ' +
		'DisplayOrder="'+ coalesce(cast(@DisplayOrder AS VARCHAR(10)),space(1)) + '" ' +
		'Creator="'+ coalesce(cast(@Creator AS VARCHAR(10)),space(1)) + '" ' +
		'StatusID="'+ coalesce(cast(@IsActive AS VARCHAR(20)),space(1)) + '" ' +
		'Language="'+ coalesce(cast(@Language AS VARCHAR(20)),space(1)) + '" ' +  
		'IP="'+ coalesce(cast(@LoginIP AS VARCHAR(50)),space(1)) + '" />'

	SET @endRun = getdate()
	SET @duration  = datediff (millisecond, @startRun, @endRun)

	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserID				= @Creator
		,@CustID			= 0
		,@SPName			= 'LA_FunctionIns'
		,@TrackingValue		= @LogSPData
		,@TrackingValue2	= @LogSPDataOld
		,@duration			= @duration
END
GO