/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210506@Percy
	DB: DBCUST.bodb_licensee
	Task: Add Charge Rate settings for BBIN, Habanero, Creative Gaming and PP Live Casino
*/

USE bodb_licensee
GO


-- Insert 3rd Party
	INSERT INTO dbo.OAS_Party (PartyName, Description, PartyType)
	SELECT ProductCode, Description, 3
	FROM (VALUES ('BBIN', 'BBIN'), ('HB', 'Habanero'), ('CG', 'Creative Gaming'), ('PPL', 'PP Live Casino')) AS t (ProductCode, Description)

--- 1. From Credit to 3rd
	DECLARE @Setting TABLE (ProductId INT, Rate MONEY, FromDate DATE, ToDate DATE, MinAmount MONEY, MaxAmount MONEY)
	INSERT INTO @Setting (ProductId, Rate, FromDate, ToDate, MinAmount, MaxAmount)
	-- BBIN
	SELECT 47, 0.04, '2020-05-19', '2050-01-01', NULL, NULL
	-- Habanero
	UNION ALL SELECT 61, 0.05, '2021-04-27', '2050-01-01', NULL, NULL
	-- Creative Gaming
	UNION ALL SELECT 62, 0.03, '2021-05-06', '2050-01-01', NULL, NULL
	-- PP Live Casino
	UNION ALL SELECT 65, 0.06, '2021-04-15', '2021-07-14', 0, 10000000000000
	--UNION ALL SELECT 65, 0.065, '2021-07-15', '2050-01-01', 0, 2000000
	--UNION ALL SELECT 65, 0.06, '2021-07-15', '2050-01-01', 2000001, 5000000
	--UNION ALL SELECT 65, 0.05, '2021-07-15', '2050-01-01', 5000001, 10000000000000

	INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount)
	SELECT s.ProductId, t.CreditParty, p.PartyId, 0, s.Rate, 1, s.FromDate, s.ToDate, s.MinAmount, s.MaxAmount
	FROM dbo.OAS_Party p WITH (NOLOCK)
		CROSS JOIN @Setting s
		CROSS JOIN (VALUES (25), (30)) AS t (CreditParty)
	WHERE p.PartyName IN ('BBIN', 'HB', 'CG', 'PPL')

--- 2. From Credit to OW
	INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
	SELECT s.ProductId, t.CreditParty, 1, 0, 0, 1, s.FromDate, s.ToDate
	FROM @Setting s
		CROSS JOIN (VALUES (25), (30)) AS t (CreditParty)

--- 3. From Deposit to OW
	DELETE @Setting

	INSERT INTO @Setting (ProductId, Rate, FromDate, ToDate, MinAmount, MaxAmount)
	-- Habanero
	SELECT 61, 0.05, '2021-04-27', '2050-01-01', NULL, NULL
	-- Creative Gaming
	UNION ALL SELECT 62, 0.03, '2021-05-06', '2050-01-01', NULL, NULL

	INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
	SELECT s.ProductId, t.LicenseeParty, p.PartyId, 0, s.Rate, 1, s.FromDate, s.ToDate
	FROM dbo.OAS_Party p WITH (NOLOCK)
		CROSS JOIN @Setting s
		CROSS JOIN (VALUES (1), (9), (11), (98)) AS t (LicenseeParty)
	WHERE p.PartyName IN ('HB', 'CG')

-- LA System Mapping
	INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId ,SystemId)
	SELECT c.ChargeId, 2
	FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
	WHERE c.FromParty IN (25, 30, 1, 9, 11, 98) 
		AND c.ToParty IN (SELECT p.PartyId FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyName IN ('HB', 'CG', 'PPL') UNION ALL SELECT 1)
		AND c.ProductId IN (47, 61, 62, 65)