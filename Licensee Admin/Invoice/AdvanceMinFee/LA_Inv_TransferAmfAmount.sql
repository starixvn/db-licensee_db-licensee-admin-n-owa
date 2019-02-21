/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_TransferAmfAmount]
	@FromPartyId		INT,
	@ToPartyId			INT,
	@Amount				MONEY,
	@Option				SMALLINT,
	@Environment		VARCHAR(50),
	@UserId				INT,
	@LoginIp			VARCHAR(50),
	@ErrCode			INT				OUTPUT,
	@ErrMsg				VARCHAR(4000)	OUTPUT
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DB052.bodb_Licensee

	Revisions:
		- 20171226: create SP
		- 20190122@Parsons: Improve AG prepayment and discount setting [#104620]
	Explanation:
		@Option: 0-Amf Prepayment Write off, 1-deduct as AMF, 2-deduct against invoice, 3-AG Prepayment write off
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Description VARCHAR(100)
	DECLARE @BillerId INT = 0
	DECLARE @InvoiceTypeId INT = 12

	DECLARE @AmfPrepaymentWriteOff INT = 0, @AGPrepaymentWriteOff INT = 3

	SET @FromPartyId = ISNULL(@FromPartyId,0)
	SET @ToPartyId = ISNULL(@ToPartyId,0)
	SET @Amount = ISNULL(@Amount,0)

	DECLARE
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		NVARCHAR(MAX)

	SET @startRun = GETDATE()

	SELECT @ErrCode = 0, @ErrMsg = ''

	-- 1 official party
	-- 5 un-official party
	DECLARE @ExistingParties TABLE(PartyId INT, PartyName VARCHAR(50))
	INSERT INTO @ExistingParties(PartyId,PartyName)
	(
		SELECT p.PartyId, p.PartyName
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
		WHERE p.PartyType IN (1,5) AND d.PartyID IN(@FromPartyId, @ToPartyId)
			AND ISNULL(d.StatusId,0) = 1
			AND ISNULL(d.IsDeposit,0) = 1
		UNION ALL SELECT 0, 'OW'
	)

	IF @FromPartyId > 0 AND NOT EXISTS (SELECT * FROM @ExistingParties WHERE PartyId=@FromPartyId)
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = 'From Licensee is not found.'
		RETURN
	END
	IF @ToPartyId > 0 AND NOT EXISTS (SELECT * FROM @ExistingParties WHERE PartyId=@ToPartyId)
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = 'To Licensee is not found.'
		RETURN
	END
	IF @ToPartyId = @FromPartyId
	BEGIN
		SELECT @ErrCode = 104, @ErrMsg = 'Cannot transfer to same licensee.'
		RETURN
	END

	-- get remaining amf, prepayment
	DECLARE @RemainingAMF MONEY = ISNULL((SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND @FromPartyId > 0
			AND s.RefPartyId = @FromPartyId
			AND s.InvItemTypeId IN (3,5,7,21)
	),0)
	DECLARE @RemainingPP MONEY = ISNULL((SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND @FromPartyId > 0
			AND s.RefPartyId = @FromPartyId
			AND s.InvItemTypeId IN (22,23,24)
	),0)

	DECLARE @Transfer TABLE(
		ItemTypeId		SMALLINT,
		RefPartyId		INT,
		[Description]	VARCHAR(100),
		Amount			MONEY
	)

	-- write off
	-- 21-amf, 23-prepayment
	IF @Option = @AmfPrepaymentWriteOff
	BEGIN
		IF @FromPartyId = 0
		BEGIN
			SELECT @ErrCode = 101, @ErrMsg = 'From Licensee is required.'
			RETURN
		END

		SET @Amount = @RemainingAMF + @RemainingPP
		SET @Description = 'Write off' + CHAR(13) + 'Amount: '
		DECLARE @WriteOffAmount MONEY = CASE WHEN @Amount<@RemainingAMF THEN @Amount ELSE @RemainingAMF END
		
		IF @RemainingAMF > 0 BEGIN
			INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
			VALUES (21, @FromPartyId, -@WriteOffAmount, @Description + CONVERT(VARCHAR, @WriteOffAmount, 1))
		END
		
		SET @WriteOffAmount = @Amount-@RemainingAMF
		IF @RemainingPP > 0 AND @WriteOffAmount > 0 BEGIN
			INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
			VALUES (23, @FromPartyId,-@WriteOffAmount, @Description + CONVERT(VARCHAR, @WriteOffAmount, 1))
		END
	END
	ELSE IF @Option = @AGPrepaymentWriteOff
	BEGIN
		IF @FromPartyId = 0
		BEGIN
			SELECT @ErrCode = 101, @ErrMsg = 'From Licensee is required.'
			RETURN
		END

		SET @Description = 'Write off' + CHAR(13) + 'Amount: '

		INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
		VALUES (27, @FromPartyId,-@Amount, @Description + CONVERT(VARCHAR, @Amount, 1))
	END
	ELSE
	BEGIN
		-- deduct as AMF
		-- deduct against monthly billing
		IF @ToPartyId = 0
		BEGIN
			SELECT @ErrCode = 101, @ErrMsg = 'To Licensee is required.'
			RETURN
		END
		IF @Amount = 0
		BEGIN
			SELECT @ErrCode = 102, @ErrMsg = 'The transfer amount is required.'
			RETURN
		END
		IF @FromPartyId > 0 AND @Amount > (@RemainingAMF+@RemainingPP)
		BEGIN
			SELECT @ErrCode = 103, @ErrMsg = 'The transfer amount must be equals to or less than remaining AMF.'
			RETURN
		END

		DECLARE @DeductText VARCHAR(100) = (CASE WHEN @Option=1 THEN 'Deduct as AMF' ELSE 'Deduct against invoice' END)
		DECLARE @FromPartyName VARCHAR(50) = (SELECT PartyName FROM @ExistingParties WHERE PartyId = @FromPartyId)
		DECLARE @ToPartyName VARCHAR(50) = (SELECT PartyName FROM @ExistingParties WHERE PartyId = @ToPartyId)

		-- transfer to
		IF @FromPartyId > 0
		BEGIN
			SET @Description = 'Transfer to ' + @ToPartyName + CHAR(13) + @DeductText + CHAR(13) + 'Amount: '
			DECLARE @TransferAmount MONEY = CASE WHEN @Amount<@RemainingAMF THEN @Amount ELSE @RemainingAMF END

			IF @RemainingAMF > 0 BEGIN
				INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
				VALUES (21, @FromPartyId, -@TransferAmount,@Description + CONVERT(VARCHAR, @TransferAmount, 1))
			END

			SET @TransferAmount = @Amount-@RemainingAMF
			IF @RemainingPP > 0 AND @TransferAmount > 0 BEGIN
				INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
				VALUES (23, @FromPartyId, -@TransferAmount,@Description + CONVERT(VARCHAR, @TransferAmount, 1))
			END
		END

		-- transfer from
		-- 3-initialize AMF
		--22-initialize prepayment
		SET @Description = 'Transfer from ' + @FromPartyName + CHAR(13) + @DeductText + CHAR(13) + 'Amount: ' + CONVERT(VARCHAR, @Amount, 1)
		INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description]) VALUES(CASE WHEN @Option=1 THEN 3 ELSE 22 END, @ToPartyId, @Amount, @Description)
	END

	INSERT INTO dbo.LA_InvoiceHeader (BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,Amount,InvoiceType,StatusId,Note,Environment,FromDate,ToDate,DueDate,HasDeleted,HasSent,CreatedBy,CreatedDateTime)
		VALUES(@BillerId, @ToPartyId, 0, '', 1, GETDATE(), @Amount, @InvoiceTypeId, 0, '', @Environment,GETDATE(),GETDATE(),GETDATE(),0,0,@UserId,GETDATE())

	DECLARE @HeaderId INT = SCOPE_IDENTITY()

	INSERT INTO dbo.LA_InvoiceStatement(InvoiceHeaderId, InvItemTypeId, RefPartyId, [Description], Income, Expense)
	SELECT @HeaderId, f.ItemTypeId, f.RefPartyId, f.[Description]
		, CASE WHEN it.GroupDB = 'Income' THEN f.Amount * it.SignDB ELSE NULL END
		, CASE WHEN it.GroupDB = 'Expense' THEN f.Amount * it.SignDB ELSE NULL END
	FROM @Transfer f
	INNER JOIN dbo.LA_InvoiceItemType it ON f.ItemTypeId = it.InvItemTypeId

	-- month of deduction
	-- deduct as AMF = 1
	IF @Option = 1 AND @Environment = 'PRO'
	BEGIN
		DECLARE @CurrencyId INT = (SELECT BaseCurrencyId FROM dbo.OAS_PartyDetail WHERE PartyID=@ToPartyId)
		UPDATE m SET MonthOfDeduction = CEILING(@Amount / m.FeeAmount)
		FROM dbo.LA_MinFee m WITH(NOLOCK)
		WHERE m.FeeTypeId=1
			AND m.PartyId = @ToPartyId
			AND m.CurrencyId = @CurrencyId
			AND GETDATE() BETWEEN m.FromDate AND m.ToDate
	END

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	DECLARE @xml XML = (
		SELECT f.ItemTypeId		AS '@iid'
			, f.RefPartyId		AS '@pid'
			, f.Amount			AS '@a'
			, f.[Description]	AS '@d'
			, @Environment		AS '@env'
		FROM @Transfer f
		FOR XML PATH('h'), TYPE)
	SET @logSPData = CAST(@xml AS NVARCHAR(MAX))

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ISNULL(ActionId,0)
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_Inv_TransferAmfAmount'

	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_Inv_TransferAmfAmount'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = ''
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP @UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = ''
			, @duration = @duration
	END CATCH
END
GO