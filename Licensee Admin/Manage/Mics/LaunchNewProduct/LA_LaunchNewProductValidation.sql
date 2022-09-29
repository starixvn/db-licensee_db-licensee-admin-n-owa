/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_LaunchNewProductValidation]
	@ProductCode	 VARCHAR(10)
	,@PlayerNameList NVARCHAR(MAX) 
	,@ErrCode		 INT = 0 OUTPUT
	,@ErrMsg		 NVARCHAR(1000) = '' OUTPUT
AS
/*
	Created: 20220919@Malcolm
	Task : Launch new licensee
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20220919@Malcolm: Launch new Product [RedmineID: #175860]
		
	Param's Explannation: 

*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductId INT
	
	SELECT @PlayerNameList = ISNULL(@PlayerNameList, '')

	SELECT @ProductId = p.ProductID
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId = p.GroupProductId AND GroupProductCode= @ProductCode

	DECLARE @Party TABLE (PartyID INT, PartyName VARCHAR(100), InvoiceLanguage VARCHAR(7), ErrCode INT)

	INSERT INTO @Party (PartyName)
	SELECT DISTINCT RTRIM(LTRIM(value)) FROM STRING_SPLIT(@PlayerNameList, ',')

	UPDATE p
		 SET p.PartyID = op.PartyID
		     ,p.InvoiceLanguage = pd.InvoiceLanguage
		     ,p.ErrCode = CASE WHEN pd.PartyID IS NULL THEN  1 -- Invalid payer name
							   WHEN op.PartyType <> 1 OR ISNULL(pd.StatusId, 0) <> 1 OR pd.TerminatedDate IS NOT NULL OR pd.SuspendedDate IS NOT NULL THEN 2 -- Not Active payer
							   WHEN lp.LicenseeID IS NULL THEN 3 -- Not offered selected product yet
							   WHEN ISNULL(n.IsLaunched, 0) = 1 THEN 4 -- Already launch the selected product
						  ELSE NULL END -- Invalid
	FROM @Party p
		LEFT JOIN dbo.OAS_Party op WITH(NOLOCK) ON op.PartyName = p.PartyName AND op.PartyType IN (1, 5)
		LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = op.PartyID AND ISNULL(pd.IsDeposit, 0) = 1
		LEFT JOIN dbo.LicenseeProduct3rd lp WITH(NOLOCK) ON lp.LicenseeID = op.OldRefID AND lp.ProductID = @ProductId
		OUTER APPLY (
			SELECT  TOP 1 1 AS IsLaunched 
			FROM dbo.OAS_ChargeInfo c WITH(NOLOCK) 
			WHERE c.FromParty = op.PartyID AND c.ProductID = @ProductId
		) AS n (IsLaunched)

	DELETE FROM @Party WHERE ErrCode IS NULL

	IF EXISTS (SELECT 1 FROM @Party)
	BEGIN
		;WITH CTE AS (
			SELECT ErrCode, STRING_AGG (PartyName, ',') WITHIN GROUP (ORDER BY PartyName ASC) AS PartyNameList
			FROM @Party
			GROUP BY ErrCode
		)
		SELECT @ErrMsg = ISNULL(@ErrMsg, '') + n.ErrMsg + ': ' + e.PartyNameList + '<br>'
		FROM CTE e
			INNER JOIN (
				VALUES (1, 'Invalid payer name')
					,(2, 'Not Active payer')
					,(3, 'Not offered selected product yet')
					,(4, 'Already launched the selected product')
			) AS n(ErrCode, ErrMsg) ON n.ErrCode = e.ErrCode
		ORDER BY n.ErrCode ASC

		SELECT @ErrMsg = STUFF(@ErrMsg, LEN(@ErrMsg) - 3, 4, ''),  @ErrCode = 101
	END

END
GO