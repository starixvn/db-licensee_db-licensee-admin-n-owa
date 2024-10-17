/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupModify]
	@PayerGroupId			INT	= 0
	, @PayerGroupName		VARCHAR(100)
	, @PayerList			VARCHAR(MAX)	= ''
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0  OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= '' OUTPUT
	, @PayerGroupIdOut		INT	= 0	OUTPUT
AS
/*  
	 Created: 20150422@Florent
	 Task : add/modify payer Group setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
	 	- 20171219@Bruce: increase length for variables [#88197]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20241016@Danny: Extend parameter data length [RemineID: #212252]
	 
	 Params:		
	 Example:
	
*/
BEGIN	
SET NOCOUNT ON
	-- For writing log
	DECLARE 
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		VARCHAR(5000),
		@logSPDataOld	VARCHAR(5000),
		@xml			XML

	-- Time start
	SET @startRun = GETDATE()

	DECLARE @PayerGroupList AS TABLE (PayerGroupId INT, PartyID INT)
	DECLARE @IsEdit BIT = 0
	-- check case edit
	IF EXISTS ( SELECT 1 FROM dbo.LA_PartyGroup WITH (NOLOCK) WHERE PartyGroupId = @PayerGroupId)
		SET @IsEdit = 1
	
	INSERT INTO @PayerGroupList(PayerGroupId, PartyID)
	SELECT @PayerGroupId, value 
	FROM STRING_SPLIT(@PayerList, ',')

	--check case insert
	IF EXISTS (SELECT 1 FROM dbo.LA_PartyGroup WITH (NOLOCK) WHERE PartyGroupName = @PayerGroupName AND @IsEdit = 0)
	BEGIN
		SELECT @ErrCode = 200
		,@ErrMsg = 'Group Name exists please try again!'
		RETURN
	END

	IF EXISTS (SELECT 1 FROM dbo.LA_PartyGroup WITH (NOLOCK) WHERE PartyGroupName = @PayerGroupName AND PartyGroupId != @PayerGroupId)
	BEGIN
		SELECT @ErrCode = 200
		,@ErrMsg = 'Group Name exists please try again!'
		RETURN
	END

	--check payer exists on another group
	IF EXISTS (SELECT 1 FROM dbo.LA_PartyGroupAssignment p WITH (NOLOCK) INNER JOIN @PayerGroupList pg ON p.PartyId = pg.PartyID AND p.PartyGroupId != @PayerGroupId)
	BEGIN 
		DECLARE @ExistsPayer VARCHAR(500)
		SELECT @ExistsPayer = COALESCE(@ExistsPayer + ', ' + p1.PartyName, p1.PartyName)
		FROM dbo.LA_PartyGroupAssignment p WITH (NOLOCK) 
			INNER JOIN @PayerGroupList pg ON p.PartyId = pg.PartyID
			INNER JOIN dbo.OAS_Party p1 WITH (NOLOCK) ON  p.PartyId = p1.PartyID AND p.PartyGroupId != @PayerGroupId		
		SELECT @ErrCode = 201
		,@ErrMsg = 'Payer(s) '+ @ExistsPayer +' exists on another group, please try again!'
		RETURN
	END

	--Case Insert New
	IF @IsEdit = 0
	BEGIN 
		INSERT INTO dbo.LA_PartyGroup (PartyGroupName)
		SELECT @PayerGroupName

		IF @@ERROR <> 0 
		BEGIN
			SELECT @ErrCode = 202
					, @ErrMsg = 'Cannot save the Payer Group, please try again!'
			RETURN
		END
				
		SET @PayerGroupIdOut = SCOPE_IDENTITY()

		INSERT INTO dbo.LA_PartyGroupAssignment(PartyGroupId, PartyId)
		SELECT @PayerGroupIdOut, l.PartyID
		FROM @PayerGroupList l 
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.PartyID = p.PartyID

		IF @@ERROR <> 0 
		BEGIN
			--rollback
			DELETE dbo.LA_PartyGroup WITH (ROWLOCK)
			WHERE PartyGroupId = @PayerGroupIdOut
			SELECT @ErrCode = 202
					, @ErrMsg = 'Cannot save the Payer Group, please try again!'
			RETURN
		END

		-- Write log
		SET @xml = (
			SELECT @PayerGroupIdOut	AS '@pid'
				, @PayerGroupName	AS '@pn'
				, PartyId			AS '@p'
			FROM dbo.LA_PartyGroupAssignment WITH (NOLOCK)
			WHERE PartyGroupId = @PayerGroupIdOut
			FOR XML PATH('z'), ROOT('r')			
			)		

		SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END
	-- Case Edit
	IF @IsEdit = 1
	BEGIN
		SET @PayerGroupIdOut = @PayerGroupId
		-- Write log
		SET @xml = (
			SELECT @PayerGroupIdOut	AS '@pid'
				, @PayerGroupName	AS '@pn'
				, PartyId			AS '@p'
			FROM dbo.LA_PartyGroupAssignment WITH (NOLOCK)
			WHERE PartyGroupId = @PayerGroupIdOut
			FOR XML PATH('z'), ROOT('r')			
			)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

		UPDATE dbo.LA_PartyGroup WITH (ROWLOCK)
		SET PartyGroupName = @PayerGroupName
		WHERE PartyGroupId = @PayerGroupId

		;MERGE dbo.LA_PartyGroupAssignment WITH( ROWLOCK, UPDLOCK) AS t
		USING @PayerGroupList AS s
		ON (t.PartyGroupId = s.PayerGroupId AND t.PartyId = s.PartyID)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT (PartyGroupId, PartyID)
			 	 VALUES (s.PayerGroupId, s.PartyID)
		WHEN NOT MATCHED BY SOURCE AND PartyGroupId = @PayerGroupIdOut AND PartyId = t.PartyId
			THEN DELETE;
		
		DELETE dbo.LA_PartyGroupAssignment WITH( ROWLOCK, UPDLOCK)
		WHERE PartyId NOT IN (SELECT PartyID FROM dbo.OAS_Party WITH (NOLOCK) WHERE PartyType = 1)
			AND PartyGroupId = @PayerGroupIdOut

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 203	
			RETURN
		END
		
		-- Write log
		SET @xml = (
			SELECT @PayerGroupIdOut	AS '@pid'
				, @PayerGroupName	AS '@pn'
				, PartyId			AS '@p'
			FROM @PayerGroupList
			FOR XML PATH('z'), ROOT('r')			
			)		

		SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_PayerGroupModify'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO