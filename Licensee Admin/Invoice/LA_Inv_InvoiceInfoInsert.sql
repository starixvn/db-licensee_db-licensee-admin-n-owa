/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoInsert]
	  @BillerId				INT
	, @PartyId				INT
	, @InvoiceSymbol		NVARCHAR(20)
	, @InvoiceNumber		INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @DueDate				DATETIME
	, @InvoiceDate			DATETIME
	, @Amount				MONEY
	, @InvoiceTypeId		SMALLINT
	, @Note					NVARCHAR(200) = ''
	, @StatementXml			NVARCHAR(MAX)
	, @IsSeparateProduct	BIT = 0
	, @UserID				INT
	, @LoginIP				VARCHAR (50) = ''
	, @HostingFeeMaxPCU		INT = 0
	, @HostingFeeRateAmount	MONEY = 0
	, @HostingFeeIsWaived	BIT = 0
	, @Environment			VARCHAR(20)
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @NewInvoiceNumber		INT						OUTPUT
	, @NewInvoiceId			INT						OUTPUT
	, @InvoiceFileName		NVARCHAR(200)	= ''	OUTPUT
AS
/*  Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20150806@Bravo: Save invoice
		- 20151019@Victor: Support Chinese on Invoice's text fields
		- 20160718@Bruce: Hosting fees - Insert hosting fees info
		- 20170421@Bruce: Add environment filter
		- 20170608@Bruce: Save details, reuse invoice no of voided invoice [#76411]
		- 20170721@Scofield: Update to save data to InvoiceStatement [#79905]
		- 20170824@Bruce: Support debit note for return AMF [#76410]
		- 20171026@Bruce: redmine id [#85256]
				- add invoice date
				- insert product id to statement
		- 20180112@Bruce: increase description length [#89417]
		- 20180131@Bruce: support credit note for setup fee [#90274]
		- 20180109@Bruce: month of deduction [#87039]
		- 20190123@Bruce: Save invoices - Increased security [#96660]
		- 20190319@bruce: Apply min fee rule for discount calculation [#109997]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210720@Percy: Check invoice number is already used [RedmineID: #147006]
		- 20220418@Percy: Remove code update InvItemTypeId [RedmineID: #164139]
		- 20240103@Danny: store invoice amount with 2 decimal digits [RedmineID: #197260]
		- 20240722@Danny:  Change Invoice File Name [#194603]
		- 20240815@Danny:  Change Invoice File Name [#209325]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CurrentTime DATETIME = GETDATE(), @NewInvoiceHeaderId INT

	-- For Log
	DECLARE @startTime DATETIME, @duration INT, @logSPData NVARCHAR(MAX)
	SET @startTime = @CurrentTime

	-- Parse XML
	DECLARE @Statement TABLE (ItemType SMALLINT, Amount MONEY, Description NVARCHAR(500), Reference NVARCHAR(100), ProductId INT)
	DECLARE @Statement_XML XML

	IF ISNULL(@StatementXml, '') <> ''
	BEGIN
		SELECT @Statement_XML = CONVERT(XML, @StatementXml)

		INSERT INTO @Statement (ItemType, Amount, Description, Reference, ProductId)
		SELECT s.ItemType, s.Amount, s.Description, s.Reference, ISNULL(p.ProductId, -1)
		FROM (
			SELECT
				t.c.value('(ItemType/text())[1]', 'SMALLINT') AS ItemType
				,t.c.value('(Amount/text())[1]', 'MONEY') AS Amount
				,t.c.value('(Description/text())[1]', 'NVARCHAR(500)') AS Description
				,t.c.value('(Reference/text())[1]', 'NVARCHAR(100)') AS Reference
				,t.c.value('(ProductCode/text())[1]', 'VARCHAR(50)') AS ProductCode
			FROM @Statement_XML.nodes('Statements/Statement') t(c)
		) s
			LEFT JOIN dbo.LA_f_Products3rd('') p ON s.ProductCode = p.ProductPrefix
		OPTION (OPTIMIZE FOR (@Statement_XML = NULL))
	END
	
	-- Validate input data
	BEGIN
		IF ISNULL(@BillerId, 0) = 0
			OR ISNULL(@PartyId, 0) = 0
			OR ISNULL(@InvoiceSymbol, '') = ''
			OR ISNULL(@InvoiceNumber, 0) <= 0
			OR ISNULL(@DueDate, '') = ''
			OR ISNULL(@StatementXml, '') = ''
			OR ISNULL(@InvoiceTypeId, 0) <= 0
			OR ISNULL(@UserID, 0) = 0
			OR ISNULL(@Environment, '') = ''
			OR @Amount IS NULL
		BEGIN
			SELECT @ErrCode = 1, @ErrMsg = 'Invalid invoice header inputs.'
			RETURN
		END

		-- Check invoice number
		IF EXISTS (
			SELECT 1
			FROM dbo.LA_InvoiceHeader WITH (NOLOCK)
			WHERE BillerId = @BillerId AND PartyId = @PartyId
				AND InvoiceSymbol = @InvoiceSymbol AND InvoiceNumber = @InvoiceNumber
				AND Environment = @Environment AND ISNULL(StatusId, 0) <> -1 -- 0: normal, -1: void, 1: closed
		)
		BEGIN
			SELECT @ErrCode = 6, @ErrMsg = 'Invoice number is in use.'
			RETURN
		END

		-- Check Reference
		DECLARE @WrongInvoiceNo NVARCHAR(200)

		IF @InvoiceTypeId IN (4, 5, 10)
		BEGIN
			-- 4 = Credit Note
			-- 5 = Debit Note
			-- 10 = Debit Note for return AMF

			-- Wrong Reference Refno
			;WITH CTE_WrongReference AS (
				SELECT DISTINCT s.Reference
				FROM @Statement s
					LEFT JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK)
						ON s.Reference = h.OfficialInvoiceNo
							AND ISNULL(h.StatusId, 0) <> -1 -- void
							AND h.PartyId = @PartyId
							AND h.BillerId = @BillerId
				WHERE h.OfficialInvoiceNo IS NULL
			)
			SELECT @WrongInvoiceNo = STUFF((SELECT ',', '''' + Reference + '''' FROM CTE_WrongReference FOR XML PATH('')), 1, 1, '')

			IF @WrongInvoiceNo IS NOT NULL
			BEGIN
				SELECT @ErrCode = 4, @ErrMsg = 'Unknown Invoice No. ' + @WrongInvoiceNo
				RETURN
			END

			-- Wrong InvItemType
			;WITH CTE_WrongReference AS (
				SELECT DISTINCT s.Reference
				FROM @Statement s
					LEFT JOIN dbo.LA_InvoiceTypeMapping m WITH (NOLOCK) ON m.InvItemTypeId = s.ItemType AND m.InvTypeId = @InvoiceTypeId
				WHERE m.InvItemTypeId IS NULL
			)
			SELECT @WrongInvoiceNo = STUFF((SELECT ',', '''' + Reference + '''' FROM CTE_WrongReference FOR XML PATH('')), 1, 1, '')

			IF @WrongInvoiceNo IS NOT NULL
			BEGIN
				SELECT @ErrCode = 5, @ErrMsg = 'Wrong Invoice No. ' + @WrongInvoiceNo + ' for this item type.'
				RETURN
			END
		END
	END

	-- Insert invoice
	BEGIN TRY
		DECLARE @BaseCurrencyId INT = 6 -- default: EUR
		SELECT  @BaseCurrencyId = ISNULL(BaseCurrencyId, 6)
		FROM dbo.OAS_PartyBaseCurrency WITH (NOLOCK)
		WHERE PartyID = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate

		DECLARE @InvoiceNo NVARCHAR(50) = CONVERT(NVARCHAR(15), @InvoiceNumber)
		SELECT  @InvoiceNo = @InvoiceSymbol + CASE WHEN @InvoiceNumber < 100 THEN RIGHT('00' + @InvoiceNo, 3) ELSE @InvoiceNo END

		DECLARE @PartyName VARCHAR(50)
		SELECT  @PartyName = REPLACE(ISNULL(NULLIF(d.BrandName, ''), p.PartyName), ' ', '-')
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyId = d.PartyId
		WHERE p.PartyId = @PartyId

		SELECT @InvoiceFileName = @InvoiceNo + ' ' + @PartyName + CASE WHEN @InvoiceTypeId = 3 THEN ' Rebates.pdf' ELSE '.pdf' END

		IF EXISTS (SELECT 1 FROM @Statement WHERE ItemType <> 28) -- 28 = Gross Discount
			SELECT @Amount = SUM(
								ISNULL(CASE WHEN t.GroupDB = 'Income' THEN s.Amount * t.SignDB END, 0)
								- ISNULL(CASE WHEN t.GroupDB = 'Expense' THEN s.Amount * t.SignDB END, 0)
							)
			FROM @Statement s
				INNER JOIN dbo.LA_InvoiceItemType t WITH (NOLOCK) ON s.ItemType = t.InvItemTypeId
			WHERE s.ItemType <> 28

		DECLARE @StatusId SMALLINT = 0

		SELECT @StatusId = CASE WHEN  ROUND(@Amount,2) = 0 THEN 1 ELSE 0 END

		INSERT INTO dbo.LA_InvoiceHeader (BillerId, PartyId, CurrencyId, InvoiceSymbol, InvoiceNumber, FromDate, ToDate, InvoiceDate, DueDate, Amount, InvoiceType, StatusId, Note, HasSent, HasDeleted, CreatedBy, CreatedDateTime, IsSeparateProduct, MaxPCU, RateAmount, IsWaived, InvoicePath, Environment, OfficialInvoiceNo, RemainingAmount)
		VALUES (@BillerId, @PartyId, @BaseCurrencyId, @InvoiceSymbol, @InvoiceNumber, @FromDate, @ToDate, @InvoiceDate, @DueDate, ROUND(@Amount,2), @InvoiceTypeId, @StatusId, @Note, 0, 0, @UserID, @CurrentTime, @IsSeparateProduct, @HostingFeeMaxPCU, @HostingFeeRateAmount, @HostingFeeIsWaived, @InvoiceFileName, @Environment, @InvoiceNo, ROUND(@Amount,2))

		SELECT @NewInvoiceHeaderId = SCOPE_IDENTITY()

		INSERT INTO dbo.LA_InvoiceStatement (InvoiceHeaderId, InvItemTypeId, Description, RefNo, RefPartyId, ProductId, Income, Expense)
		SELECT @NewInvoiceHeaderId, s.ItemType, s.Description, s.Reference, @PartyId, s.ProductId
			,CASE WHEN t.GroupDB = 'Income' THEN s.Amount * t.SignDB ELSE NULL END AS Income
			,CASE WHEN t.GroupDB = 'Expense' THEN s.Amount * t.SignDB ELSE NULL END AS Expense
		FROM @Statement s
			INNER JOIN dbo.LA_InvoiceItemType t WITH (NOLOCK) ON s.ItemType = t.InvItemTypeId

		-- Update month of deduction
		DECLARE @AMF MONEY
		SELECT  @AMF = SUM(Amount) FROM @Statement WHERE ItemType = 3 -- AMF

		IF @InvoiceTypeId = 7 AND ISNULL(@AMF, 0) > 0 AND @Environment IN ('PRO', 'LOCAL', 'DEV')
		BEGIN
			UPDATE m SET MonthOfDeduction = CEILING(@AMF / m.FeeAmount)
			FROM dbo.LA_MinFee m WITH(NOLOCK)
			WHERE m.FeeTypeId=1
				AND m.PartyId = @PartyId
				AND m.CurrencyId = @BaseCurrencyId
				AND @InvoiceDate BETWEEN m.FromDate AND m.ToDate
		END
	END TRY
	BEGIN CATCH
		DELETE dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @NewInvoiceHeaderId
		DELETE dbo.LA_InvoiceStatement WHERE InvoiceHeaderId = @NewInvoiceHeaderId

		SELECT @ErrCode = 3, @ErrMsg = 'Insert invoice failed.' -- System error
		RETURN
	END CATCH

	-- Insert successfully
	SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully.', @NewInvoiceNumber = @InvoiceNumber, @NewInvoiceId = @NewInvoiceHeaderId

	-- Write Log
	SET @duration = DATEDIFF(MILLISECOND, @startTime, GETDATE())
	DECLARE @xml XML = (
		SELECT @NewInvoiceId	AS '@hid'
			,@BillerId			AS '@b'
			,@PartyId			AS '@p'
			,@BaseCurrencyId	AS '@c'
			,@InvoiceSymbol		AS '@is'
			,@InvoiceNumber		AS '@in'
			,@InvoiceDate		AS '@ivd'
			,@DueDate			AS '@dd'
			,@Amount			AS '@amt'
			,@InvoiceTypeId		AS '@ivt'
			,0					AS '@stt'
			,@Note				AS '@n'
			,0					AS '@hs'
			,0					AS '@hd'
			,@UserID			AS '@cb'
			,@CurrentTime		AS '@crd'
			,@CurrentTime		AS '@upd'
			,@InvoiceFileName	AS '@fn'
			,@IsSeparateProduct	AS '@sp'
			,@HostingFeeIsWaived	AS '@hfw'
			,@HostingFeeMaxPCU		AS '@hfpcu'
			,@HostingFeeRateAmount	AS '@hfam'
			,(SELECT 
				@NewInvoiceId	AS '@hid'
				,Description	AS '@d'
				,Amount			AS '@amt'
				,ItemType		AS '@at'
				,Reference		AS '@rn'
			FROM @Statement
			FOR XML PATH('d'), TYPE)
		FOR XML PATH('h'), TYPE)
	
	SET @logSPData = CAST(@xml AS NVARCHAR(MAX))

	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_Inv_InvoiceInfoInsert'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= ''
END
GO