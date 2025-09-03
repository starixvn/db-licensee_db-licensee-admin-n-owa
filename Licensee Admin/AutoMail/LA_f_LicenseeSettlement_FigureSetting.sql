/*<info serverAlias="DBLIC-bodb_licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION [dbo].[LA_f_LicenseeSettlement_FigureSetting] (
	@ProductIds VARCHAR(4000)
)
RETURNS TABLE 
AS
/*  Created: 20240517@Danny
	DB: DBLIC-bodb_licensee
		
	Revisions:
		- 20240517@Danny: Create func.  [#204167]
		- 20241004@Sally: Support Odds Boost Voucher [#209884]
		- 20250505@Corbin: Integrate HOTDOG [#221605]
		- 20250505@Corbin: Integrate Microgaming Live Casino [#223409]
		- 20250505@Corbin: Integrate RichGaming [RemineID:#225057]
		- 20250820@Danny: Virtual Sports 2 - Offer Tournament Prize [#235167]

*/

RETURN 
(
	WITH t AS
	(								
 		SELECT '0' AS ProductIDs, 'Date, Currency, Turnover, Total Trans, Gross Win_Customer Win Loss, Gross Win_Odds Boost Bonus, Gross Win_Total, <Licensee Name> Win Loss, Amount Due To <Licensee Name>_Gross Win * Charge Rate, Amount Due To <Licensee Name>_Odds Spread Cost, Amount Due To <Licensee Name>_Total, <Billing Currency> equivalent' AS Cols
		UNION ALL
		SELECT '10,100', 'Date, Currency, Turnover, Total Trans, Gross Win_Customer Win Loss, Gross Win_Contribution, Gross Win_Total, <Licensee Name> Win Loss, Amount due to <Product Name>_Gross Win * Charge Rate, Amount due to <Product Name>_Contribution, Amount due to <Product Name>_Jackpot Prize, Amount due to <Product Name>_Total, <Billing Currency> equivalent'
		UNION ALL
		SELECT '5,21,34,45,55,73,79,80,87,89,95,103,107,108', 'Date, Currency, Turnover, Total Trans, Customer Win Loss, <Licensee Name> Win Loss, <Licensee Name> Charge Rate, Promotion, Company, <Billing Currency> equivalent'  
		UNION ALL
		SELECT '39', 'Date, Currency, Turnover, Total Trans, Customer Win Loss, <Licensee Name> Win Loss, Tips Amount, Tips Amount Due, Company, <Billing Currency> equivalent'
		UNION ALL
		SELECT '42', 'Date, Currency, Turnover, Total Trans, Gross Win_Customer Win Loss, Gross Win_Contribution, Gross Win_Total, <Licensee Name> Win Loss, Amount due to <Product Name>_Gross Win * Charge Rate, Amount due to <Product Name>_Contribution, Amount due to <Product Name>_Free Bets ,Amount due to <Product Name>_Jackpot Prize, Amount due to <Product Name>_Total, <Billing Currency> equivalent'
		UNION ALL
		SELECT '66', 'Date, Currency, Turnover, Total Trans, Gross Win_Customer Win Loss, Gross Win_Contribution, Gross Win_Total, <Licensee Name> Win Loss, Amount due to <Product Name>_Gross Win * Charge Rate, Amount due to <Product Name>_Contribution, Amount due to <Product Name>_Free Bets ,Amount due to <Product Name>_Jackpot Prize,  Amount due to <Product Name>_Promotion, Amount due to <Product Name>_Total, <Billing Currency> equivalent'
		UNION ALL
		SELECT '32,36','Date, Currency, Turnover, Total Trans, Gross Win_Customer Win Loss, Gross Win_Contribution, Gross Win_Total, <Licensee Name> Win Loss, Amount due to <Product Name>_Gross Win * Charge Rate, Amount due to <Product Name>_Contribution, Amount due to <Product Name>_Jackpot Prize,  Amount due to <Product Name>_Promotion, Amount due to <Product Name>_Total, <Billing Currency> equivalent'
	), t_default AS
	(
		SELECT STRING_AGG(CAST (p3.Productid AS VARCHAR(20)),',') AS Productids, 'Date, Currency, Turnover, Total Trans, Customer Win Loss, <Licensee Name> Win Loss, Company, <Billing Currency> equivalent' AS Cols
		FROM Product3rd p3 WITH(NOLOCK)
		LEFT JOIN ( 
			SELECT pd.ProductID FROM t
			CROSS APPLY  ( 
				SELECT CAST(value AS INT) as ProductID FROM STRING_SPLIT(t.ProductIDs,',')
			) pd
		) pd ON p3.Productid = pd.ProductID
		WHERE pd.ProductID IS NULL AND p3.EndOfSupportDate IS NULL
	)
	SELECT  pd.ProductID  ProductID, 
			CASE WHEN  pd.ProductID = 0 THEN 'SB' ELSE p3.ProductPrefix END ProductPrefix, 
			CASE WHEN  pd.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END ProductName,
			c.Col, 
			c.Group_ 
	FROM  ( SElECT ProductIDs, Cols FROM t UNION ALL SElECT ProductIDs, Cols FROM t_default )t
	CROSS APPLY ( 
		SELECT CAST(value AS INT) as ProductID FROM STRING_SPLIT(t.ProductIDs,',')
	) pd
	CROSS APPLY 
	(
	SELECT	CASE WHEN CHARINDEX('_', value) >0 THEN TRIM(SUBSTRING(value,CHARINDEX('_', value)+1, LEN(value))) ELSE trim(value) END Col, 
			CASE WHEN CHARINDEX('_', value) >0 THEN TRIM(SUBSTRING(value,1,CHARINDEX('_', value)-1)) END Group_ 
	FROM  STRING_SPLIT(t.Cols, ',')
	)	 c
	LEFT JOIN Product3rd p3 WITH(NOLOCK) ON pd.ProductID = p3.Productid
	WHERE pd.ProductID IN (SELECT x.Value FROM STRING_SPLIT(@ProductIds,',') x) OR @ProductIds = ''

)