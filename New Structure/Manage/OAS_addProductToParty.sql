USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_addProductToParty]    Script Date: 06/01/2015 14:29:05 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[OAS_addProductToParty] 
	 @ProductName			NVARCHAR(10)
	, @FromParty			NVARCHAR(50)
	, @ToParty				NVARCHAR(50)
	, @ParentChargeID		INT				= 0
	, @Fromdate				DATETIME
	, @Todate				DATETIME
	, @ChargeType			INT				= 1
	, @Rate					MONEY
	, @MinAmount			MONEY			= NULL
	, @MaxAmount			MONEY			= NULL
	, @Minfee				INT				= 0
	, @MinFeeCurrencyID		INT				= 0
	, @WaiveMonth			INT				= 0
	, @System				NVARCHAR(10)	= 'OA'

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
SET NOCOUNT ON

DECLARE	@oldRefID	    INT
	    , @fromPartyID  INT
	    , @toPartyID    INT
	    , @ChargeID	    INT
	    , @ProductID    INT

SELECT @oldRefID = LicenseeID 
	FROM dbo.licensees WITH (NOLOCK) 
	WHERE LicenseeName = @fromParty

SELECT @toPartyID = PartyID 
	FROM dbo.OAS_Party WITH (NOLOCK) 
	WHERE PartyName = @toParty

SELECT @ProductID = p.Productid		
FROM dbo.Product3rd p WITH (NOLOCK) 
WHERE p.ProductPrefix = @ProductName

IF (@ProductName = 'SB' OR @ProductName = 'TT')
    SET @ProductID = 0

--Insert to dbo.OAS_Party
--check exist
IF NOT EXISTS(SELECT TOP 1 1 FROM dbo.OAS_Party WITH (NOLOCK) WHERE OldRefID =@oldRefID)
BEGIN
	INSERT INTO dbo.OAS_Party (PartyName, Description, PartyType, OldRefID)
	SELECT LicenseeName, Description, 1, LicenseeID
		FROM dbo.licensees WITH (NOLOCK)
		WHERE LicenseeName = @fromParty	
END

SELECT @fromPartyID = p.PartyID
FROM dbo.OAS_Party p WITH (NOLOCK)
	INNER JOIN dbo.Licensees l WITH (NOLOCK) ON p.OldRefID = l.LicenseeID
WHERE OldRefID = @oldRefID

--Insert to dbo.OAS_PartyDetail
--check exist
IF NOT EXISTS(SELECT TOP 1 1 
				FROM dbo.OAS_PartyDetail WITH (NOLOCK)
				WHERE PartyID IN (SELECT p.PartyID
									FROM dbo.OAS_Party p  WITH (NOLOCK)
									INNER JOIN dbo.licensees l WITH (NOLOCK) ON p.OldRefID = l.LicenseeID
								 WHERE OldRefID = @oldRefID)
			 )
BEGIN
	INSERT INTO dbo.OAS_PartyDetail( PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm)
	SELECT @fromPartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm
		FROM dbo.licensees WITH (NOLOCK)
		WHERE LicenseeName = @fromParty
END 

--param anlysiz
IF (@ProductID = 0 AND @ChargeType = 1) --SB
BEGIN
	SELECT @MinAmount = NULL, @MaxAmount = NULL
END
ELSE IF (@ProductID = 0 AND @ChargeType = 2) --TT
BEGIN
	SELECT @Minfee = NULL, @MinFeeCurrencyID = NULL
END
ELSE 
BEGIN
	SELECT @MinAmount = NULL, @MaxAmount = NULL, @Minfee = NULL, @MinFeeCurrencyID = NULL
END

--Insert to OAS_ChargeInfo
--contrains

IF EXISTS(SELECT TOP 1 1 FROM dbo.OAS_Party WITH (NOLOCK) WHERE OldRefID = @oldRefID AND PartyType = 1)
BEGIN --insert old party
	SELECT @fromPartyID=partyID
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.Licensees l WITH (NOLOCK) on p.OldRefID = l.LicenseeID
		WHERE OldRefID = @oldRefID
END

IF NOT EXISTS (SELECT TOP 1 1 
			FROM dbo.OAS_ChargeInfo with (NOLOCK)
			WHERE ProductID = @ProductID 
				 AND FromParty = @fromPartyID 
				 AND ToParty = @toPartyID 
				 AND ChargeType = @ChargeType
				 AND (
					  (@fromDate BETWEEN FromDate AND ToDate
					  OR @todate BETWEEN FromDate AND ToDate)
					OR 
					(FromDate BETWEEN @fromdate AND @todate
					 AND ToDate BETWEEN @fromdate AND @todate
					))					 
			)
BEGIN	
	INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount)
	   SELECT @ProductID, @fromPartyID, @toPartyID, @ParentChargeID, @Rate, @ChargeType, @fromDate, @toDate, @MinAmount, @MaxAmount

	SELECT @ChargeID = MAX(ci.ChargeID) 
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)

	--add system mapping
	INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
	    SELECT @ChargeID, s.id
	    FROM dbo.Systems s WITH (NOLOCK)
	    WHERE s.SystemName IN (SELECT val FROM bodb02.dbo.strSplit(@System,',')) 
	    GROUP BY s.id
	-- add Minfee and WaiveMonth
	IF (@WaiveMonth = NULL OR @WaiveMonth = 0)
		BEGIN
			SET @fromdate = NULL
		END

	IF (@ProductID = 0 AND @ChargeType = 1)
	    INSERT INTO dbo.LA_ChargeInfo_MinFee (ChargeID, MinFee, MinFeeCurrencyID, WaiveFrom, WaiveTo)
	    SELECT @ChargeID, @MinFee, @MinFeeCurrencyID, @fromdate, DATEADD( DAY, -1, DATEADD(MONTH, @WaiveMonth, @fromdate))

	SELECT 'Suceess! ' + CHAR(13)
	-- Show result
	SELECT ci.ChargeID
			, s.SystemName
			, ci.ProductID
			, p1.PartyName AS FromParty
			, p1.PartyID
			, p2.PartyName AS ToParty
			, p2.PartyID
			, ci.ParentChargeID
			, ci.ChargeType
			, ci.Rate
			, ci.FromDate
			, ci.ToDate
			, ci.MinAmount
			, ci.MaxAmount
			, cm.MinFee
			, cm.MinFeeCurrencyID
			, cm.WaiveFrom
			, cm.WaiveTo
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID 
		LEFT JOIN dbo.LA_ChargeInfo_MinFee cm ON ci.ChargeID = cm.ChargeID
		INNER JOIN dbo.OAS_Party p1 ON ci.FromParty = p1.PartyID
		INNER JOIN dbo.OAS_Party p2 ON ci.ToParty = p2.PartyID
		INNER JOIN (SELECT DISTINCT s.id, s.SystemName
							FROM dbo.Systems s WITH (NOLOCK)
							WHERE s.SystemName IN (SELECT val FROM bodb02.dbo.strSplit(@System,','))) s ON cs.SystemID = s.id
	WHERE ci.ChargeID = @ChargeID
END
ELSE
BEGIN
	PRINT  'Please check data again!'
END

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_addProductToParty] TO [vnteam] 