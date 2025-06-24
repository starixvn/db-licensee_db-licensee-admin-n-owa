/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_SabaPlay_SettlementReport_LicenseeListSel]
	 @UserID		INT	   = 0
	,@FunctionKey	NVARCHAR(100)	= ''
AS
/*  Created: 20250403@Danny
	Task : Report - SabaPlay Licensee Settlement Report - Load Licensee dropdown 
	DB: DBLIC.bodb_licensee

	Revisions:
		- 20250403@Danny: create new sp
		- 20250513@Eddie: Enhance SP [RedmineID: #226204]
		- 20250520@Eddie: Change ParentName for SabaPlay [RedmineID: #220534]
		- 20250624@Danny: return all operators in case of @UserID = 0 [RedmineID: #217743]

	Param's Explanation:



*/
BEGIN
	SET NOCOUNT ON

	DROP TABLE IF EXISTS #userFunctionParty
	CREATE TABLE #userFunctionParty (
		PartyID		INT, 
		PartyName	NVARCHAR(100), 
		OldRefID	INT, 
		BrandName	VARCHAR(100)
	)

	DECLARE @FunctionID INT, @BillerID INT

	SELECT @BillerID =  PartyId
	FROM dbo.LA_BillerInfo WITH(NOLOCK) WHERE BillerNameAbbreviation = 'RHL'

	IF(@FunctionKey = '')
	BEGIN
		SET @FunctionID = 0
	END
	ELSE
	BEGIN
		SELECT @FunctionID = FunctionID FROM LA_Function WITH(NOLOCK) WHERE FunctionKey = @FunctionKey
	END	

	IF (@USERID > 0 AND @FunctionID > 0 ) --get Party List By User and Function
	BEGIN
		INSERT INTO #userFunctionParty(PartyID, PartyName, OldRefID, BrandName)
		SELECT up.PartyID, op.PartyName, op.OldRefID, opd.BrandName
		FROM dbo.LA_UserParty Up WITH (NOLOCK)
			INNER JOIN OAS_Party op WITH (NOLOCK) ON Up.PartyID = op.PartyID
			INNER JOIN OAS_PartyDetail opd WITH (NOLOCK) ON op.PartyID = opd.PartyID
		    INNER JOIN dbo.LA_UserFunction UF WITH (NOLOCK) ON up.UserID = uf.UserID --permission of user
		    INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON up.PartyID = fp.PartyID
			    AND uf.FunctionID = fp.FunctionID --permission of Function - Party
		WHERE up.UserID = @userID
			AND fp.FunctionID = @FunctionID
			AND op.PlatformId = 2 AND op.PartyType = 1

	END

	IF (@USERID = 0 AND @FunctionID > 0) --get list Party assign to 1 Function
	BEGIN
		INSERT INTO #userFunctionParty(PartyID, PartyName, OldRefID, BrandName)
		SELECT  fp.PartyID, op.PartyName, op.OldRefID, opd.BrandName
		FROM dbo.LA_FunctionParty fp WITH (NOLOCK)
		INNER JOIN OAS_Party op WITH (NOLOCK) ON fp.PartyID = op.PartyID
		INNER JOIN OAS_PartyDetail opd WITH (NOLOCK) ON op.PartyID = opd.PartyID
		WHERE fp.FunctionID = @FunctionID AND op.PlatformId = 2 AND op.PartyType = 1		
	END

	; WITH t AS
	(
		SELECT	t.PartyID, 
				ISNULL(t.BrandName,t.PartyName) PartyName, 
				9999  AS ParentID, 
				'Reasternhold Licensees' AS ParentName,
				t.OldRefID AS  OperatorID,
				x.x AS ProductList
		FROM #userFunctionParty t
		OUTER APPLY
		(
			SELECT 
			(
				SELECT lis.ProductId , sp.ProductName
				FROM LA_InvoiceSetting lis WITH(NOLOCK)
				INNER JOIN bodb_LicenseeReport.dbo.SabaPlay_Products sp WITH(NOLOCK) ON lis.ProductId = sp.ProductID
				WHERE lis.FromPartyId = t.PartyID AND lis.ToPartyId = @BillerID  AND lis.ProductId IS NOT NULL 
				FOR JSON PATH
			) x
		)x
		WHERE t.OldRefID IS NOT NULL
	)
	SELECT PartyID, PartyName, ParentID, ParentName, OperatorID, ProductList
	FROM t

	UNION ALL
	SELECT DISTINCT ParentID AS  PartyID, ParentName AS PartyName, NULL AS ParentID,NULL AS  ParentName, NULL AS OperatorID, NULL AS ProductList
	FROM t

	ORDER BY ParentID, PartyID



	
END

