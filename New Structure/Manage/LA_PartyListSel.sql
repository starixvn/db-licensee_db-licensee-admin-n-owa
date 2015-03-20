USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_PartyListSel]    Script Date: 01/12/2014 14:42:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PartyListSel]
	 @UserID		INT	   = 0
	,@FunctionID	INT	   = 0
AS
/*  
	 Created: 20140814@Florent
	 Task : get List Party of 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
		  - 20141031@Florent: Apply new Structure Using SystemMapping
		  - 20150312@Florent: add column brandname and fix case without SB
	 Params:
		+ UserID : 
			- 0 get list Party of All user
		+ FunctionID : 
			- 0 get list Party when config in manage User		
*/
SET NOCOUNT ON

DECLARE @suffix_Licensee NVARCHAR(20) = 'Licensees'
DECLARE @tmpCompany	AS TABLE (PartyID INT)
DECLARE @tmpLicensee AS TABLE (Fromdate DATETIME,PartyID INT,PartyGroupID INT)
DECLARE @CreditLicensee	AS TABLE (PartyID INT)

INSERT INTO @CreditLicensee
SELECT PartyID 
FROM dbo.OAS_Party WITH (NOLOCK)
WHERE PartyName IN ('IBC','18bb')

INSERT INTO @tmpCompany
SELECT PartyID 
FROM dbo.OAS_Party WITH (NOLOCK)
WHERE PartyName IN ('ONEWorks','Boping')

SELECT MAX(ci.FromDate) FromDate, ci.FromParty
INTO #ListParty
FROM OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN
		(
		SELECT MIN(ci.ProductID) AS ProductID, FromParty
		   FROM dbo.OAS_Party p WITH (NOLOCK)
			   INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		   WHERE ChargeType = 1 AND p.PartyType = 1
		   GROUP BY FromParty
		) p ON ci.ProductID = p.ProductID AND ci.FromParty = p.FromParty
WHERE ci.ChargeType = 1
GROUP BY ci.FromParty

--get list licensee with lastest config
INSERT INTO @tmpLicensee (Fromdate, PartyID, PartyGroupID)
SELECT DISTINCT ci.FromDate, ci.FromParty, ci.ToParty
FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
	INNER JOIN #ListParty p ON ci.FromDate = p.Fromdate AND ci.FromParty = p.FromParty
	INNER JOIN @tmpCompany tc ON ci.ToParty = tc.PartyID
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cm WITH (NOLOCK) ON ci.ChargeID = cm.ChargeID
WHERE ci.ChargeType = 1 
    AND cm.SystemID = 2
    AND ci.FromParty NOT IN ( SELECT PartyID FROM @CreditLicensee)

BEGIN
	CREATE TABLE #Party (
		PartyID			INT
		,PartyGroupID	INT)

	CREATE TABLE #data (
		PartyID			INT
		, PartyName		NVARCHAR(100)
		, BrandName		NVARCHAR(100)
		, ParentID		INT)

	IF (@FunctionID = 0 AND @UserID > 0) --get list Party of 1 User		
	BEGIN
		
		INSERT INTO #Party(PartyID, PartyGroupID)
		(
			SELECT l.PartyID AS PartyID
				,l.PartyGroupID AS PartyGroupID
			FROM dbo.LA_UserParty Up WITH (NOLOCK)		    
				INNER JOIN @tmpLicensee l ON up.PartyID = l.PartyID
			WHERE Userid = @UserID
			UNION --get credit	  
			SELECT p.PartyID
				,999
			FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN dbo.LA_UserParty UP WITH (NOLOCK) ON p.PartyID = up.PartyID
			WHERE pd.IsDeposit = 0
				AND UP.UserID = @userID
		)
	END

	IF (@USERID = 0 AND @FunctionID > 0) --get list Party assign to 1 Function
	BEGIN
		INSERT INTO #Party(PartyID, PartyGroupID)
		(
			SELECT l.PartyID AS PartyID
				,l.PartyGroupID AS PartyGroupID
			FROM dbo.LA_FunctionParty FP WITH (NOLOCK)
				INNER JOIN @tmpLicensee l ON fp.PartyID = l.PartyID
			WHERE FP.FunctionID = @FunctionID			
			UNION --get credit	  		
			SELECT p.PartyID
				,999
			FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON p.PartyID = FP.PartyID
			WHERE pd.IsDeposit = 0
				AND FP.FunctionID = @FunctionID
		)
	END

	IF (@USERID > 0 AND @FunctionID > 0 ) --get Party List By User and Function
	BEGIN
		SELECT up.PartyID, Up.UserID, fp.FunctionID, Up.StatusID
		INTO #userFunctionParty
		FROM dbo.LA_UserParty Up WITH (NOLOCK)
		    INNER JOIN dbo.LA_UserFunction UF WITH (NOLOCK) ON up.UserID = uf.UserID --permission of user
		    INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON up.PartyID = fp.PartyID
			    AND uf.FunctionID = fp.FunctionID --permission of Function - Party
		WHERE up.UserID = @userID
			AND fp.FunctionID = @FunctionID
				
		INSERT INTO #Party(PartyID, PartyGroupID)
		(
			SELECT l.PartyID AS PartyID
				,l.PartyGroupID AS PartyGroupID
			FROM #userFunctionParty A
			INNER JOIN @tmpLicensee l ON A.PartyID = l.PartyID
			WHERE A.Userid = @UserID
				AND a.FunctionID = @FunctionID
			UNION
			SELECT p.PartyID
				,999
			FROM OAS_Party p
			INNER JOIN OAS_PartyDetail pd ON p.PartyID = pd.PartyID
			INNER JOIN #userFunctionParty ufp ON p.PartyID = ufp.PartyID
			WHERE pd.IsDeposit = 0
				AND ufp.Userid = @UserID
				AND ufp.FunctionID = @FunctionID
		)

		DROP TABLE #userFunctionParty
	END
END

IF (@USERID = 0 AND @FunctionID = 0 ) --getAll Party List 
BEGIN
	INSERT INTO #Party(PartyID, PartyGroupID)
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
END

--parse by ParentID
INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
SELECT p.PartyGroupID
	,CASE 
		WHEN op.PartyName IS NOT NULL
			THEN op.PartyName
		ELSE 'Credit'
		END + ' ' + @suffix_Licensee
	, '' BrandName
	,0 AS ParentID
FROM #Party p
	LEFT JOIN dbo.Oas_Party op WITH (NOLOCK) ON p.PartyGroupID = oP.Partyid
GROUP BY p.PartyGroupID
	,CASE 
		WHEN op.PartyName IS NOT NULL
			THEN op.PartyName
		ELSE 'Credit'
		END

INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
SELECT d.PartyID
	, CASE op.PartyName
		WHEN 'IBC' THEN 'FDL'
		WHEN '18bb'THEN 'PIH'
		ELSE op.PartyName
	END AS PartyName
	, ISNULL(pd.BrandName,'') AS BrandName
	, a.PartyGroupID
FROM #Party d
    INNER JOIN (
	    SELECT PartyGroupID
	    FROM #Party
	    GROUP BY PartyGroupID
	    ) a ON d.PartyGroupID = a.PartyGroupID
    LEFT JOIN dbo.OAS_Party op WITH (NOLOCK) ON d.PartyID = op.PartyID AND op.PartyType = 1
	LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON op.PartyID = pd.PartyID   	

SELECT PartyID, PartyName, BrandName, ParentID
FROM #data
ORDER BY ParentID
	,PartyID
	

DROP TABLE #Party
DROP TABLE #data
DROP TABLE #ListParty
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PartyListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PartyListSel] TO bodbAdminNet 
