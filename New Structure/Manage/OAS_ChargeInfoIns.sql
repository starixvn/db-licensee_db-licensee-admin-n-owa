USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_addProductToParty]    Script Date: 06/01/2015 14:29:05 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[OAS_ChargeInfoIns] 
	@ProductName			NVARCHAR(10)
	, @FromPartyName		NVARCHAR(50)
	, @ToPartyName			NVARCHAR(50)
	, @FromDate				DATE
	, @ToDate				DATE
	, @ChargeType			INT = 1
	, @Rate					MONEY
	, @MinAmount			MONEY = NULL
	, @MaxAmount			MONEY = NULL
	, @Minfee				INT = 0
	, @MinFeeCurrencyId		INT = 0
	, @WaiveMonth			INT = 0
	, @System				NVARCHAR(10) = 'OA'
	, @IsDebug				BIT = 1
	, @ChargeId				INT OUTPUT
AS
/*
	Created: 20140424@Florent
	Task : Add new charge into OAS_ChargeInfo
	Base : 
	DB: DB052.bodb_licensee

	Revisions:
		- 20140506@Florent: get exact name of licensee
		- 20140506@Florent: Remove CharIndex()
		- 20140924@Florent: add product AG Casino
		- 20141126@Florent: using new structure of table OAS_ChargeInfo and add Waive values

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
	WHERE PartyName = @ToPartyName

	SELECT @ProductID = p.ProductId
	FROM dbo.Product3rd p WITH (NOLOCK)
	WHERE p.ProductPrefix = @ProductName

	IF (@ProductName = 'SB'	OR @ProductName = 'TT')
		SET @ProductID = 0

	--insert OAS_Party if doesn't exists
	SELECT @FromPartyId = PartyID
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE OldRefID = @OldRefId AND PartyType = 1

	IF @FromPartyId IS NULL
	BEGIN

		INSERT INTO dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID)
		SELECT LicenseeName, [Description], 1, LicenseeID
		FROM dbo.licensees WITH (NOLOCK)
		WHERE LicenseeName = @FromPartyName

		SET @FromPartyId = SCOPE_IDENTITY()

		--insert party detail if doesn't exists
		IF NOT EXISTS (SELECT TOP 1 1
			FROM dbo.OAS_PartyDetail WITH (NOLOCK)
			WHERE PartyID = @FromPartyId)
		BEGIN
			INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm)
			SELECT @FromPartyId, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm
			FROM dbo.licensees WITH (NOLOCK)
			WHERE LicenseeName = @FromPartyName
		END
	END
	
	--param anlysiz
	IF (@ProductID = 0 AND @ChargeType = 1) --charge in winloss
	BEGIN
		SELECT @MinAmount = NULL, @MaxAmount = NULL
	END
	ELSE IF (@ProductID = 0	AND @ChargeType = 2) --charge in total transaction
	BEGIN
		SELECT @Minfee = NULL, @MinFeeCurrencyID = NULL
	END
	ELSE
	BEGIN
		SELECT @MinAmount = NULL, @MaxAmount = NULL, @Minfee = NULL, @MinFeeCurrencyID = NULL
	END

	--get parent chargeid
	--SELECT @ParentChargeId = MAX(ChargeID)
	--FROM dbo.OAS_ChargeInfo WITH(NOLOCK)
	--WHERE FromParty = @ToPartyId
	--	AND ProductID = @ProductId
	--	AND @FromDate BETWEEN FromDate AND ToDate

	--incase charge direct
	IF @ParentChargeId IS NULL
		SET @ParentChargeId = 0

	--insert chargeinfo if doesn't exists or overlap data
	IF NOT EXISTS (SELECT TOP 1 1
			FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
			WHERE ProductID = @ProductID
				AND FromParty = @FromPartyID
				AND ToParty = @ToPartyID
				AND ChargeType = @ChargeType
				AND ((@FromDate BETWEEN FromDate AND ToDate
						OR @Todate BETWEEN FromDate	AND ToDate)
					OR (FromDate BETWEEN @FromDate AND @ToDate
						AND ToDate BETWEEN @Fromdate AND @Todate)
					)
			)
	BEGIN
		INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, Remark)
		SELECT @ProductID, @FromPartyId, @ToPartyId, @ParentChargeId, @Rate, @ChargeType, @FromDate, @ToDate, @MinAmount, @MaxAmount, @Remark

		SELECT @ChargeId = SCOPE_IDENTITY()

		--add system mapping
		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT @ChargeId, s.id
		FROM dbo.Systems s WITH (NOLOCK)
		WHERE s.SystemName IN (SELECT val FROM bodb02.dbo.strSplit(@System, ','))
		
		--reset waivemonth
		IF (ISNULL(@WaiveMonth, '') = '' OR @WaiveMonth = 0)
		BEGIN
			SET @FromDate = NULL
		END

		--insert minfee
		IF (@ProductID = 0 AND @ChargeType = 1)
		BEGIN
			INSERT INTO dbo.LA_ChargeInfo_MinFee (ChargeID, MinFee, MinFeeCurrencyID, WaiveFrom, WaiveTo)
			SELECT @ChargeID, @MinFee, @MinFeeCurrencyID, @FromDate, DATEADD(DAY, - 1, DATEADD(MONTH, @WaiveMonth, @FromDate))
		END

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
GRANT VIEW DEFINITION ON [dbo].[OAS_ChargeInfoIns] TO [vnteam] 