USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingModify] 	
	@PayerID				INT	
	, @PayerGroupId			INT				= 0
	, @DiscountGroupId		INT				= 0
	, @RebateGroupId		INT				= 0
	, @ChargeSettingXML		VARCHAR (MAX)
	, @MinFeeSettingXML		VARCHAR (MAX)
	, @WaiveSettingXML		VARCHAR (MAX)
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
	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()
	
	DECLARE @OldPayerGroupId INT, @MinFeeInsertedList VARCHAR(100), @WaiveInsertedList VARCHAR(100)

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
	--Payer Discount
	EXEC dbo.LA_PayerDiscountAssignmentModify
		@PayerList			= @PayerID
		, @DiscountGroupId	= @DiscountGroupId
		, @UserID			= @UserID
		, @Mode				= 'A'
		, @LoginIP			= @LoginIP
		, @ErrCode			= @ErrCode	OUTPUT
		, @ErrMsg			= @ErrMsg	OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId <> @DiscountGroupId AND @OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			RETURN
		END
	--Payer rebate
	EXEC dbo.LA_PayerDiscountAssignmentModify
		@PayerList			= @PayerID
		, @DiscountGroupId	= @RebateGroupId
		, @UserID			= @UserID
		, @Mode				= 'A'
		, @LoginIP			= @LoginIP
		, @ErrCode			= @ErrCode	OUTPUT
		, @ErrMsg			= @ErrMsg	OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId <> @DiscountGroupId AND @OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback discount
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @DiscountGroupId
			RETURN
		END
	--Minfee
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @MinFeeSettingXML
		, @ExchangeID			= @ExchangeID
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @MinFeeInsertedList  OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId <> @DiscountGroupId AND @OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback discount
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @DiscountGroupId
			--Rollback rebate
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @RebateGroupId
			RETURN
		END
	--Waive
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @WaiveSettingXML
		, @ExchangeID			= @ExchangeID
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @WaiveInsertedList OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId <> @DiscountGroupId AND @OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback discount
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @DiscountGroupId
			--Rollback rebate
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @RebateGroupId
			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@MinFeeInsertedList, ','))
			RETURN
		END
	--Modify Chargerate Setting
	EXEC dbo.LA_ChargeRateSettingModify
		@PayerID				= @PayerID
		, @ChargeSettingXML		= @ChargeSettingXML
		, @ExchangeID			= @ExchangeID
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT			

	IF @ErrCode <> 0 
		BEGIN
			--Rollback for payerGroup
			IF (@OldPayerGroupId <> @DiscountGroupId AND @OldPayerGroupId = 0)
				DELETE dbo.LA_PartyGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID
			--Rollback discount
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @DiscountGroupId
			--Rollback rebate
			DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID AND DiscountGroupId = @RebateGroupId
			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@MinFeeInsertedList, ','))
			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM bodb02.dbo.strSplit(@WaiveInsertedList, ','))
			RETURN
		END
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerSettingModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerSettingModify] TO bodbAdminNet