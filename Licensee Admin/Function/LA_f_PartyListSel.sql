/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO
ALTER FUNCTION dbo.LA_f_PartyListSel()
RETURNS @data TABLE (PartyID INT, PartyName NVARCHAR(100), BrandName NVARCHAR(100), ParentID INT ) 
AS 

/*
	Created: 20200214@Sophia
	Task : Function get List Party of 
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20200214@Sophia: initial [redmine: #128471]
		- 20231228@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
	
	Copy from : LA_PartyListSel , remember to maintain together with this SP, (mode userID = 0, FunctionKey = '')
	Params:
*/
 BEGIN 


DECLARE @suffix_Licensee NVARCHAR(20) = 'Licensees'
DECLARE @tmpCompany	AS TABLE (PartyID INT)
DECLARE @tmpLicensee AS TABLE (Fromdate DATETIME,PartyID INT,PartyGroupID INT)
DECLARE @CreditLicensee	AS TABLE (PartyID INT)

INSERT INTO @CreditLicensee
SELECT PartyID FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE ISNULL(IsDeposit,0) = 0

INSERT INTO @tmpCompany
SELECT PartyID 
FROM dbo.OAS_Party WITH (NOLOCK)
WHERE PartyID IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )

DECLARE @ListParty AS TABLE (FromDate DATETIME, FromParty  INT)  
INSERT INTO @ListParty (FromDate,FromParty ) 
SELECT MAX(ci.FromDate) FromDate, ci.FromParty
FROM OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN
		(
		SELECT MIN(ci.ProductID) AS ProductID, FromParty
		   FROM dbo.OAS_Party p WITH (NOLOCK)
			   INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			   INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
		   WHERE ChargeType = 1 AND p.PartyType = 1
		   GROUP BY FromParty
		) p ON ci.ProductID = p.ProductID AND ci.FromParty = p.FromParty
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping c WITH(NOLOCK) ON ci.ChargeID = c.ChargeID AND c.SystemID = 2
WHERE ci.ChargeType = 1
GROUP BY ci.FromParty

--get list licensee with lastest config
INSERT INTO @tmpLicensee (Fromdate, PartyID, PartyGroupID)
SELECT DISTINCT ci.FromDate, ci.FromParty, ci.ToParty
FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
	INNER JOIN @ListParty p ON ci.FromDate = p.Fromdate AND ci.FromParty = p.FromParty
	INNER JOIN @tmpCompany tc ON ci.ToParty = tc.PartyID
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cm WITH (NOLOCK) ON ci.ChargeID = cm.ChargeID
WHERE ci.ChargeType = 1 
    AND cm.SystemID = 2
    AND ci.FromParty NOT IN ( SELECT PartyID FROM @CreditLicensee)


DECLARE @Party AS TABLE  (
	PartyID			INT
	,PartyGroupID	INT)

	INSERT INTO @Party(PartyID, PartyGroupID)
	(
		SELECT l.PartyID AS PartyID
			,l.PartyGroupID AS PartyGroupID
		FROM dbo.OAS_Party P WITH (NOLOCK)
			 INNER JOIN @tmpLicensee l ON p.PartyID = l.PartyID
		WHERE p.PartyType = 1
		UNION --get credit	  
		SELECT p.PartyID
			,999
		FROM dbo.OAS_Party p
		INNER JOIN dbo.OAS_PartyDetail pd ON p.PartyID = pd.PartyID
		WHERE pd.IsDeposit = 0
	)

--parse by ParentID
INSERT INTO @data (PartyID, PartyName, BrandName, ParentID)
SELECT p.PartyGroupID
	,CASE 
		WHEN op.PartyName IS NOT NULL
			THEN op.PartyName
		ELSE 'Credit'
		END + ' ' + @suffix_Licensee
	, '' BrandName
	,0 AS ParentID
FROM @Party p
	LEFT JOIN dbo.Oas_Party op WITH (NOLOCK) ON p.PartyGroupID = oP.Partyid
GROUP BY p.PartyGroupID
	,CASE 
		WHEN op.PartyName IS NOT NULL
			THEN op.PartyName
		ELSE 'Credit'
		END

INSERT INTO @data (PartyID, PartyName, BrandName, ParentID)
SELECT d.PartyID
	, CASE op.PartyName
		WHEN 'IBC' THEN 'FDL'
		WHEN '18bb'THEN 'PIH'
		ELSE op.PartyName
	END AS PartyName
	, ISNULL(pd.BrandName,'') AS BrandName
	, a.PartyGroupID
FROM @Party d
    INNER JOIN (
	    SELECT PartyGroupID
	    FROM @Party
	    GROUP BY PartyGroupID
	    ) a ON d.PartyGroupID = a.PartyGroupID
    LEFT JOIN dbo.OAS_Party op WITH (NOLOCK) ON d.PartyID = op.PartyID AND op.PartyType = 1
	LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON op.PartyID = pd.PartyID   	

RETURN

END 

