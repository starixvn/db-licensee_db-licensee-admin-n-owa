/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_lap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[OAS_ChargeInfoIns] 
	@ProductName			NVARCHAR(10)
	, @FromPartyName		NVARCHAR(50)
	, @ToPartyName			NVARCHAR(50)
	, @FromDate				DATE
	, @ToDate				DATE
	, @ChargeType			INT				= 1
	, @Rate					MONEY
	, @RateSettingXML		XML				= NULL
	, @MinAmount			MONEY			= NULL
	, @MaxAmount			MONEY			= NULL
	, @Minfee				INT				= 0
	, @BaseCurrencyId		INT				= 0
	, @WaiveMonth			INT				= 0
	, @System				NVARCHAR(10)	= 'OA'
	, @Remark				NVARCHAR(200)	= NULL
	, @BasicOfBilling		NVARCHAR(4000)  = NULL
	, @IsDebug				BIT				= 1
	, @ChargeId				INT OUTPUT
AS
/*
	Created: 20140424@Florent
	Task: Add new charge into OAS_ChargeInfo
	Base: 
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20140506@Florent: get exact name of licensee
		- 20140506@Florent: Remove CharIndex()
		- 20140924@Florent: add product AG Casino
		- 20141126@Florent: using new structure of table OAS_ChargeInfo and add Waive values
		- 20150412@Patrick: Add filter by PartyType
		- 20150616@Florent: rename param @MinfeeCurrencyId to @BaseCurrencyId
							- add data to LA_Minfee for minfee and waive time
		- 20150813@Florent: support multicharge rate - Microgaming
		- 20160315@Victor: support Microgaming - RNG product
		- 20161214@Jim:Invoice - Setup fees [RedmineID : #65260 ]
		- 20170309@Harper: Add BaseCurrencyID For MinFee and PartyDetail
		- 20170808@Harper: Fix case MinFee = 0 [RedmineID: #81327]
		- 20170912@Harper: Clear code [RedmineID: #82673] 
		- 20171012@Harper: Add more Basic Of Billing Info [#84772]
		- 20180122@Harper: Add code for insert Month of deduction for LA_MinFee [RedmineID: #87039]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]

	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @OldRefId INT, @FromPartyId INT, @ToPartyId INT, @ProductId INT, @ParentChargeId INT = 0

	IF ISNULL(@Remark, '') = ''
	BEGIN
		SELECT 'Enter remark please!!!'
		RETURN 
	END
	SET @Remark = @Remark + ', created date: ' + CONVERT(VARCHAR(20), GETDATE(), 101)

	SELECT @OldRefId = LicenseeID
	FROM dbo.licensees WITH (NOLOCK)
	WHERE LicenseeName = @FromPartyName
	
	SELECT @ToPartyId = PartyID
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE PartyName = @ToPartyName AND PartyType NOT IN (4)

	SELECT @ProductID = p.ProductId
	FROM dbo.Product3rd p WITH (NOLOCK)
	WHERE p.ProductPrefix = @ProductName

	IF (@ProductName = 'SB'	OR @ProductName = 'TT')
		SET @ProductID = 0

	-------------------------------------------* OAS_PARTY *-------------------------------------
	SELECT @FromPartyId = PartyID
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE OldRefID = @OldRefId AND PartyType = 1

	IF @FromPartyId IS NULL
	BEGIN
		SELECT @FromPartyId = PartyID
		FROM dbo.OAS_Party WITH (NOLOCK)
		WHERE PartyName = @FromPartyName AND PartyType = 5
		
		IF ISNULL(@FromPartyId, 0)= 0
		BEGIN
			INSERT INTO dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID)
			SELECT LicenseeName, [Description], 1, LicenseeID
			FROM dbo.licensees WITH (NOLOCK)
			WHERE LicenseeName = @FromPartyName

			SET @FromPartyId = SCOPE_IDENTITY()
		END
		ELSE 
		BEGIN
			UPDATE dbo.OAS_Party  
			SET OldRefID   = @OldRefId
				,SetupName = PartyName
				,PartyType = 1
				,PartyName = @FromPartyName
			WHERE PartyID = @FromPartyId
		END	

		-------------------------------------------* OAS_PARTY DETAIL *-------------------------------------
		IF NOT EXISTS ( SELECT TOP 1 1
						FROM dbo.OAS_PartyDetail WITH (NOLOCK)
						WHERE PartyID = @FromPartyId
						)
		BEGIN
			INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, BaseCurrencyId)
			SELECT @FromPartyId, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, @BaseCurrencyId
			FROM dbo.licensees WITH (NOLOCK)
			WHERE LicenseeName = @FromPartyName
		END
	END
	
	-------------------------------------------* OAS_CHARGEINFO *-------------------------------------
	
	IF (@ProductID = 0 AND @ChargeType = 1) --charge in winloss
	BEGIN
		SELECT @MinAmount = NULL, @MaxAmount = NULL
	END
	ELSE IF (@ProductID = 0	AND @ChargeType = 2) --charge in total transaction
	BEGIN
		SELECT @Minfee = NULL, @BaseCurrencyId = NULL
	END
	ELSE
	BEGIN
		SELECT @MinAmount = NULL, @MaxAmount = NULL, @Minfee = NULL, @BaseCurrencyId = NULL
	END

	--incase charge direct
	IF @ParentChargeId IS NULL
		SET @ParentChargeId = 0

	--insert chargeinfo if doesn't exists or overlap data
	IF NOT EXISTS ( SELECT TOP 1 1
					FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
					WHERE ProductID = @ProductID
						AND FromParty = @FromPartyID
						AND ToParty = @ToPartyID
						AND ChargeType = @ChargeType
						AND ((@FromDate BETWEEN FromDate AND ToDate	OR @Todate BETWEEN FromDate	AND ToDate)
							OR (FromDate BETWEEN @FromDate AND @ToDate AND ToDate BETWEEN @Fromdate AND @Todate))
				)
	BEGIN
		IF @ProductId IN (14, 17) -- case Microgaming
		BEGIN
			INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
			SELECT @ProductID, @FromPartyId, @ToPartyId, @ParentChargeId, NULL, @ChargeType, @FromDate, @ToDate, @MinAmount, @MaxAmount, @Remark, @BaseCurrencyId, @FromDate, @BasicOfBilling

			SELECT @ChargeId = SCOPE_IDENTITY()
			-- parse XML
			DECLARE @ChargeInfoSub AS TABLE (ProductId INT, BettypeRef INT,	FromParty INT, ToParty INT, ParentChargeID INT, Rate MONEY, ChargeType INT, FromDate DATE, ToDate DATE, MinAmount MONEY, MaxAmount MONEY, BaseCurrencyId INT, FirstOfBilling DATE, BasicOfBilling VARCHAR (100),ChargeIdRef INT) 	
			DECLARE @ChargeIdInserted AS TABLE (ChargeID INT)
			DECLARE @idoc AS INT
			EXEC sp_xml_preparedocument @idoc OUTPUT, @RateSettingXML

			INSERT INTO @ChargeInfoSub(ProductId, BettypeRef, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId, FirstOfBilling, BasicOfBilling, ChargeIdRef)
			SELECT @ProductID, BettypeRef, @FromPartyId, @ToPartyId, ParentChargeID, Rate, @ChargeType, FromDate, ToDate, @MinAmount, @MaxAmount, BaseCurrencyId, @FromDate, @BasicOfBilling, @ChargeId
			FROM OPENXML(@idoc, 'ChargeInfoSub/Sub') 
			WITH (
				BettypeRef			INT		'BettypeRef'
				, ParentChargeID	INT		'ParentChargeID'
				, Rate				MONEY	'Rate'
				, FromDate			DATE	'FromDate'
				, ToDate			DATE	'ToDate'
				, BaseCurrencyId	INT		'BaseCurrencyId'					
			) 
			EXEC sp_xml_removedocument @idoc

			IF @@ERROR <> 0
			BEGIN
				DELETE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) WHERE ChargeID = @ChargeId
				SELECT 'Error!!! Please check again', @ProductID AS '@ProductId', @FromPartyID AS '@FromPartyId', @ToPartyId AS '@ToPartyId'
						, @ChargeType AS '@ChargeType', @FromDate AS '@FromDate', @ToDate AS '@ToDate', @ParentChargeId AS '@ParentChargeId'
						, @RateSettingXML AS '@RateSettingXML'
				RETURN
			END

			INSERT INTO dbo.OAS_ChargeInfoSub(ProductId, BettypeRef, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId, FirstOfBilling, BasisOfBilling, ChargeIdRef)
			OUTPUT INSERTED.ChargeID
			INTO @ChargeIdInserted
			SELECT ProductId, BettypeRef, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId, FirstOfBilling, BasicOfBilling, ChargeIdRef				
			FROM @ChargeInfoSub
				
			IF @@ERROR <> 0
			BEGIN
				DELETE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) WHERE ChargeID = @ChargeId
				SELECT 'Error!!! Please check again', @ProductID AS '@ProductId', @FromPartyID AS '@FromPartyId', @ToPartyId AS '@ToPartyId'
						, @ChargeType AS '@ChargeType', @FromDate AS '@FromDate', @ToDate AS '@ToDate', @ParentChargeId AS '@ParentChargeId'
						, @RateSettingXML AS '@RateSettingXML'
				RETURN
			END
		END
		ELSE
		BEGIN
			INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
			SELECT @ProductID, @FromPartyId, @ToPartyId, @ParentChargeId, @Rate, @ChargeType, @FromDate, @ToDate, @MinAmount, @MaxAmount, @Remark, @BaseCurrencyId, @FromDate, @BasicOfBilling

			SELECT @ChargeId = SCOPE_IDENTITY()

			--reset waivemonth
			IF (ISNULL(@WaiveMonth, '') = '' OR @WaiveMonth = 0)
			BEGIN
				SET @FromDate = NULL
			END

			--insert minfee
			IF (@ProductID = 0 AND @ChargeType = 1)
			BEGIN
				INSERT INTO dbo.LA_ChargeInfo_MinFee (ChargeID, MinFee, MinFeeCurrencyID, WaiveFrom, WaiveTo)
				SELECT @ChargeID, @MinFee, @BaseCurrencyId, @FromDate, DATEADD(DAY, - 1, DATEADD(MONTH, @WaiveMonth, @FromDate))

				IF (@Minfee <> 0)
				BEGIN
					DECLARE @MinFeeID INT, @AMF MONEY

					INSERT INTO dbo.LA_MinFee(PartyId, FeeTypeId, ProductId, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, Priority)
					SELECT c.FromParty, 1, c.ProductID, @MinFee, @BaseCurrencyId, c.FromDate, c.ToDate , '', 1
					FROM dbo.OAS_ChargeInfo c WITH (NOLOCK) 
					WHERE c.ChargeID = @ChargeId

					SELECT @MinFeeID = SCOPE_IDENTITY()

					-- Caculate Month of Deduction
					SELECT @AMF = SUM(ISNULL(d.Income, 0))
					FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
						INNER JOIN dbo.LA_InvoiceStatement d WITH (NOLOCK) ON h.InvoiceHeaderId = d.InvoiceHeaderId
					 WHERE h.InvoiceType = 7 AND d.InvItemTypeId = 3 AND h.StatusId <> -1 AND h.Environment = 'PRO'					
						AND h.PartyId = @FromPartyId
						AND h.CurrencyId = @BaseCurrencyId

					IF ISNULL(@AMF, 0) <> 0
					BEGIN
						UPDATE dbo.LA_MinFee
						SET MonthOfDeduction = CEILING(@AMF / @Minfee)
						WHERE MinFeeId = @MinFeeID
					END
				END

				IF (ISNULL(@WaiveMonth, '') <> '' AND @WaiveMonth <> 0) 
				BEGIN
					INSERT INTO dbo.LA_MinFee(PartyId, FeeTypeId, ProductId, FeeAmount, FromDate, ToDate, MinFeeTerm, Priority)
					SELECT c.FromParty, 2, c.ProductID, NULL, @FromDate, DATEADD(DAY, - 1, DATEADD(MONTH, @WaiveMonth, @FromDate)), NULL, 2
					FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
					WHERE c.ChargeID = @ChargeId
				END
			END
		END

		--add system mapping
		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT @ChargeId, s.id
		FROM dbo.Systems s WITH (NOLOCK)
		WHERE s.SystemName IN (SELECT value FROM STRING_SPLIT(@System, ','))

	END
	ELSE
	BEGIN
		IF @IsDebug = 1
		BEGIN
			SELECT 'Error!!! Please check again', @ProductID AS '@ProductId', @FromPartyID AS '@FromPartyId', @ToPartyId AS '@ToPartyId'
				, @ChargeType AS '@ChargeType', @FromDate AS '@FromDate', @ToDate AS '@ToDate', @ParentChargeId AS '@ParentChargeId'
		END
	END
END
GO