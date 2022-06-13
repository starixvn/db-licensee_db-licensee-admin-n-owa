/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionPartysModify]
	 @FunctionID	INT
	,@PartyIDs		VARCHAR(5500) --'1,2,3,4'
	,@Creator		INT
	,@Language		VARCHAR(20)	 = 'en-us'
	,@LoginIP		VARCHAR(30)	 =''
	,@ErrCode		INT			 = 0	    OUTPUT  
	,@ErrMsg		NVARCHAR(1000)	 = ''     OUTPUT 
AS
/*  
	Created: 20140820@Florent
	Task : Assign party(s) to Function
	DB: DBCUST.bodb_Licensee  
	
	Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @startRun  DATETIME
		,@endRun	    DATETIME
		,@duration    INT
		,@LogSPData   VARCHAR(5000)
		,@LogSPData2  VARCHAR(5000)

	SET @startRun = GETDATE()

	IF EXISTS (
			SELECT TOP 1 1
			FROM dbo.LA_FunctionParty fp WITH (NOLOCK)
			WHERE fp.FunctionID = @FunctionID
			)
	BEGIN
		DECLARE @PartyListOld VARCHAR(5000) = ''

		SELECT @PartyListOld = @PartyListOld + cast(PartyID AS VARCHAR(30)) + ','
		FROM dbo.LA_FunctionParty WITH (NOLOCK)
		WHERE FunctionID = @FunctionID

		SELECT @LogSPData2 = '<LA_FunctionPartysModify FunctionID="' + coalesce(cast(@FunctionID AS VARCHAR(10)), space(1)) + '" '
													+ 'PartyID="' + coalesce(@PartyListOld, space(1)) + '" '
													+ 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" '
													+ 'UserID="' + coalesce(cast(@Creator AS VARCHAR(20)), space(1)) + '" '
													+ 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'

		DELETE dbo.LA_FunctionParty WITH (ROWLOCK, UPDLOCK)
		WHERE FunctionID = @FunctionID

		IF @@Error > 0
		BEGIN
			SELECT @ErrCode = 1
				,@ErrMsg = 'Fail to	unassign LicenseeID ' + @PartyListOld + ' from FunctionID ' + CONVERT(VARCHAR(10), @FunctionID)

			RETURN
		END
	END

	INSERT INTO dbo.LA_FunctionParty (
		FunctionID
		,PartyID
		)
	SELECT @FunctionID
		,value AS PartyID
	FROM STRING_SPLIT(@PartyIDs, ',')

	IF @@Error > 0
	BEGIN
		SELECT @ErrCode = 1
			,@ErrMsg = 'Fail to insert data of Party list : ' + CONVERT(VARCHAR(10), @PartyIDs) + ' and FunctionID ' + CONVERT(VARCHAR(10), @FunctionID)

		RETURN
	END

	SELECT @LogSPData = '<LA_FunctionPartysModify FunctionID="' + coalesce(cast(@FunctionID AS VARCHAR(10)), space(1)) + '" '
												+ 'PartyID="' + coalesce(@PartyIDs, space(1)) + '" '
												+ 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" '
												+ 'UserID="' + coalesce(cast(@Creator AS VARCHAR(20)), space(1)) + '" '
												+ 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'

	SET @endRun = getdate()
	SET @duration = datediff(millisecond, @startRun, @endRun)

	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserID				= @Creator
		,@CustID			= 0
		,@SPName			= 'LA_FunctionPartysModify'
		,@TrackingValue		= @LogSPData
		,@TrackingValue2	= @LogSPData2
		,@duration			= @duration
END
GO