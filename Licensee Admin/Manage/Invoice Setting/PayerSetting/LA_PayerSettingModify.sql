/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingModify]
	@PayerID				INT	
	, @PayerGroupId			INT				= 0
	, @ChargeSettingXML		NVARCHAR (MAX)
	, @MinFeeSettingXML		NVARCHAR (MAX)
	, @WaiveSettingXML		NVARCHAR (MAX)
	, @ExchangeID			INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
		- 20150918@Victor: Support Chinese on Settings
		- 20170220@bruce: update payer settings [#70050]
		- 20180706@bruce: enhance discount group [#94282]

	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	
	DECLARE @OldPayerGroupId INT, @MinFeeInsertedList VARCHAR(100), @WaiveInsertedList VARCHAR(100)

	IF (@ExchangeID IS NULL) SET @ExchangeID = (SELECT ISNULL(BaseCurrencyId, 0) FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE PartyID = @PayerID)

	--backup old data
	SELECT @OldPayerGroupId = ISNULL(a.PartyGroupId, 0) FROM dbo.LA_PartyGroupAssignment a WITH (NOLOCK) WHERE a.PartyId = @PayerID	
	-- Payer Group Assignment
	IF (ISNULL(@OldPayerGroupId, 0) = 0)
	BEGIN	
		EXEC dbo.LA_PayerGroupAssignmentModify
			@PayerList			= @PayerID
			, @PayerGroupId		= @PayerGroupId
			, @UserID			= @UserID
			, @Mode				= 'A' -- case add
			, @LoginIP			= @LoginIP
			, @ErrCode			= @ErrCode	OUTPUT
			, @ErrMsg			= @ErrMsg	OUTPUT
		IF @ErrCode <> 0 
			BEGIN
				RETURN
			END
	END

	--Minfee
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @MinFeeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @MinFeeInsertedList  OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			RETURN
		END
	--Waive
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @WaiveSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @WaiveInsertedList OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@MinFeeInsertedList, ','))
			RETURN
		END
	--Modify Chargerate Setting
	EXEC dbo.LA_ChargeRateSettingModify
		@PayerID				= @PayerID
		, @ChargeSettingXML		= @ChargeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT			

	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@MinFeeInsertedList, ','))
			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@WaiveInsertedList, ','))
			RETURN
		END

	-- update payer setting
	DECLARE @startRun DATETIME = GETDATE()
	DECLARE @OldExchangeID INT = (SELECT ISNULL(BaseCurrencyId, 0) FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE PartyID = @PayerID)
	IF (@ExchangeID <> ISNULL(@OldExchangeID, 0))
	BEGIN
		--build log string
		DECLARE @logSPDataOld VARCHAR(200) = (
			SELECT @PayerID			AS '@fp'
				, @OldExchangeID	AS '@e'
			FOR XML PATH('z'), ROOT('r')
		)

		UPDATE dbo.OAS_PartyDetail WITH(ROWLOCK, UPDLOCK)
		SET BaseCurrencyId = @ExchangeID
		WHERE PartyID = @PayerID

		DECLARE @logSPData VARCHAR(200) = (
			SELECT @PayerID		AS '@fp'
				, @ExchangeID	AS '@e'
			FOR XML PATH('z'), ROOT('r')
		)
		DECLARE @endRun DATETIME = GETDATE()
		DECLARE @duration INT = DATEDIFF(MILLISECOND, @startRun, @endRun) 
		DECLARE @ActionID INT = 0

		SELECT @ActionID = ActionId
		FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
		WHERE SPName = 'LA_PayerSettingModify'

		--Write Log
		BEGIN TRY
			EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
				@UserId = @UserID
				, @IP = @LoginIP
				, @LicenseeID = 0
				, @CurrencyID = 0
				, @SPName = 'LA_PayerSettingModify'
				, @CustId = 0
				, @ActionId = @ActionID
				, @Duration = @duration
				, @Data = @logSPData
				, @OldData = @logSPDataOld
		END TRY
		BEGIN CATCH
			EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
				@UserID = @UserID
				, @CustID = 0
				, @ActionID = @ActionID
				, @TrackingValue = @LogSPData
				, @TrackingValue2 = @logSPDataOld
				, @duration = @duration
		END CATCH
	END
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_PayerSettingModify] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_PayerSettingModify] TO bodbAdminNet
GO