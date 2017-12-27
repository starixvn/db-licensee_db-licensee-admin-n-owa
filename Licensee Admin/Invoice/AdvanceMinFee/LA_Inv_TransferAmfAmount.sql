/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

CREATE PROCEDURE [dbo].[LA_Inv_TransferAmfAmount]
	@FromPartyId		INT,
	@ToPartyId			INT,
	@Amount				MONEY,
	@ItemTypeId			SMALLINT,
	@Environment		VARCHAR(50),
	@UserId				INT,
	@LoginIp			VARCHAR(50),
	@ErrorCode			INT				OUTPUT,
	@ErrorMsg			VARCHAR(4000)	OUTPUT
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DB052.bodb_Licensee

	Revisions:
		- 20171226: create SP
*/
BEGIN
	SET NOCOUNT ON
	DECLARE
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		NVARCHAR(MAX)

	SET @startRun = GETDATE()

	SELECT @ErrorCode = 0, @ErrorMsg = ''

	DECLARE @ExistingParties TABLE(PartyId INT, PartyName VARCHAR(50))
	INSERT INTO @ExistingParties(PartyId,PartyName)
	(
		SELECT p.PartyId, p.PartyName
		FROM dbo.OAS_Party p
		INNER JOIN dbo.OAS_PartyDetail d ON p.PartyID=d.PartyID
		WHERE p.PartyType=1 AND d.PartyID IN(@FromPartyId, @ToPartyId)
			AND ISNULL(d.StatusId,0) = 1
			AND ISNULL(d.IsDeposit,0) = 1
	)

	IF ISNULL(@FromPartyId,0) > 0 AND NOT EXISTS (SELECT * FROM @ExistingParties WHERE PartyId=@FromPartyId)
	BEGIN
		SELECT @ErrorCode = 100, @ErrorMsg = 'From Licensee is not found.'
		RETURN
	END
	IF ISNULL(@ToPartyId,0) > 0 AND NOT EXISTS (SELECT * FROM @ExistingParties WHERE PartyId=@ToPartyId)
	BEGIN
		SELECT @ErrorCode = 100, @ErrorMsg = 'To Licensee is not found.'
		RETURN
	END

	DECLARE @RemainingAmf TABLE (Amount MONEY) 
	INSERT INTO @RemainingAmf
	EXEC dbo.LA_Inv_RemainingAmfGet @PartyId = @FromPartyId, @Environment=@Environment

	DECLARE @Transfer TABLE(
		ItemTypeId		SMALLINT,
		RefPartyId		INT,
		[Description]	VARCHAR(100),
		Amount			MONEY
	)

	-- write off
	IF @ItemTypeId = 1
	BEGIN
		IF ISNULL(@FromPartyId,0) = 0
		BEGIN
			SELECT @ErrorCode = 101, @ErrorMsg = 'From Licensee is required.'
			RETURN
		END

		INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description])
		SELECT TOP 1 @ItemTypeId, @FromPartyId, ISNULL(r.Amount,0),'Write off' + CHAR(13) + 'Amount: ' + CONVERT(VARCHAR, r.Amount, 1)
		FROM @RemainingAmf r
	END
	ELSE
	BEGIN
		-- deduct as AMF
		-- deduct against monthly billing
		IF ISNULL(@ToPartyId,0) = 0
		BEGIN
			SELECT @ErrorCode = 101, @ErrorMsg = 'To Licensee is required.'
			RETURN
		END
		IF ISNULL(@Amount,0) = 0
		BEGIN
			SELECT @ErrorCode = 102, @ErrorMsg = 'The transfer amount is required.'
			RETURN
		END
		IF ISNULL(@FromPartyId,0) > 0 AND EXISTS (SELECT * FROM @RemainingAmf WHERE ISNULL(Amount,0) < @Amount)
		BEGIN
			SELECT @ErrorCode = 103, @ErrorMsg = 'The transfer amount must be equals to or less than remaining AMF.'
			RETURN
		END

		DECLARE @Description VARCHAR(100)
		DECLARE @DeductText VARCHAR(100) = (CASE WHEN @ItemTypeId = 2 THEN 'Deduct as AMF' ELSE 'Deduct against invoice' END)
		DECLARE @FromPartyName VARCHAR(50) = (SELECT PartyName FROM @ExistingParties WHERE PartyId = @FromPartyId)
		DECLARE @ToPartyName VARCHAR(50) = (SELECT PartyName FROM @ExistingParties WHERE PartyId = @ToPartyId)

		-- transfer to
		IF ISNULL(@FromPartyId,0) > 0
		BEGIN
			SET @Description = 'Transfer to ' + @ToPartyName + CHAR(13) + @DeductText + CHAR(13) + 'Amount: ' + CONVERT(VARCHAR, @Amount, 1)
			INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description]) VALUES(@ItemTypeId, @FromPartyId, -@Amount, @Description)
		END

		-- transfer from
		SET @Description = 'Transfer' + ISNULL((' from ' + @FromPartyName), '') + CHAR(13) + @DeductText + CHAR(13) + 'Amount: ' + CONVERT(VARCHAR, @Amount, 1)
		INSERT INTO @Transfer(ItemTypeId, RefPartyId, Amount, [Description]) VALUES(@ItemTypeId, @ToPartyId, @Amount, @Description)
	END

	INSERT INTO dbo.LA_InvoiceStatement(InvoiceHeaderId, InvItemTypeId, RefPartyId, [Description], Income, Expense)
	SELECT 0, f.ItemTypeId, f.RefPartyId, f.[Description]
		, CASE WHEN it.GroupDB = 'Income' THEN f.Amount * it.SignDB ELSE NULL END
		, CASE WHEN it.GroupDB = 'Expense' THEN f.Amount * it.SignDB ELSE NULL END
	FROM @Transfer f
	INNER JOIN dbo.LA_InvoiceItemType it ON f.ItemTypeId = it.InvItemTypeId

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	DECLARE @xml XML = (
		SELECT f.ItemTypeId		AS '@iid'
			, f.RefPartyId		AS '@pid'
			, f.Amount			AS '@a'
			, f.[Description]	AS '@d'
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

GRANT EXECUTE ON [dbo].[LA_Inv_TransferAmfAmount] TO bodbAdminNet
GO
