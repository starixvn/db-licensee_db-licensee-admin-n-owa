/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_PaymentAllocationSel]
	@PartyIDs				 VARCHAR(MAX) = '',
	@Environment			 VARCHAR(10) = 'LOCAL',
	@IsHaveAtLeastOneOpenDoc BIT = 1

AS

/*
	Created: 20231122@Danny
	DB: DBCUST.bodb_Licensee
	Task:  payment allocation 
   
	Revisions: 
		- 20230908@Danny: Initialize SP [#194603]

	Param's Explanation:

	EXEC [LA_Statement_PaymentAllocationSel]
		@PartyIDs='697,14,493,556,557,562,558,316,459,771,772,15,142,95,39,8470,353,58,8483,655,460,7207,2954,43,457,8464,898,4053,1932,526,153,101,4042,4082,699,7378,698,4079,2986,1945,2987,865,2996,2955,7201,7243,4051,8489,693,4060,4055,5116,383,453,654,530,218,448,555,589,520,591,598,599,7419,4018,7382,2991,7267,7344,739,7351,7323,7379,7410,4019,46,676,271,489,7231,2992,2989,4052,3012,890,7340,685,89,354,843,766,4059,4048,498,210,815,688,686,150,91,78,83,461,804,253,5086,790,650,491,154,260,675,7377,47,692,533,848,849,850,851,852,660,661,8491,8486,7366,7412,84,77,4062,7392,2990,1937,85,477,814,5109,8485,8478,452,7416,709,170,475,571,572,573,574,575,899,368,5093,570,5147,897,690,707,5091,8492,583,584,151,465,19,136,312,586,175,33,276,7330,40,521,171,167,194,4075,7383,5115,728,671,672,7387,7432,470,696,472,466,464,455,2970,2957,7237,1930,7262,4033,879,740,1947,7314,4041,7185,7374,1943,7421,2980,4077,2956,7226,700,7236,1903,7271,148,275,61,462,856,7217,7370,7407,7418,1948,7261,1935,7301,7341,3003,7384,7332,7254,2983,7327,7355,3002,7440,7230,6184,710,7225,1952,5085,7286,7295,1933,7247,1951,7239,3006,7334,651,694,7364,1953,7232,1946,1954,4057,7317,7257,896,7244,7386,7252,7372,7280,737,7258,7304,2993,7234,7245,7353,7417,7310,665,2999,525,789,7189,7216,7251,7300,1919,1910,415,158,895,56,59,447,682,334,41,72,482,749,750,3014,124,8476,7415,691,875,68,7442,769,773,774,776,768,67,433,471,34,777,778,779,780,781,782,387,846,796,797,798,802,803,805,819,467,7319,7441,403,24,647,494,834,74,840,841,429,213,7413,1911,346,412,217,396,207,652,331,411,367,822,821,825,839,845,7446,754,1908,831,715,730,7284,7312,885,5095,829,827,838,837,7333,7313,7431,8477,347,1913,1907,495,332,7393,7406,76,792,745,165,398,1912,770,7350,866,7285,3007,7218,7363,2963,7299,7437,2965,854,884,7365,3008,7296,7246,7362,7203,887,1914,1915,1917,1920,1916,8480,7438,695,7439,439,531,414,168,449,582,402,664,662,663,1922,590,593,595,596,597,600,7292,1934,8473,7238,886,8465,1918,869,4015,882,7400,7256,7227,2967,7449,7361,7275,7447,736,1949,7376,7305,1926,7326,7343,7409,8481,7273,7298,441,481,581,127,143,71,653,169,891,893,894,73,246,456,166,80,36,1928,417,3011,7205,876,877,7411,7405,874,903,7211,7265,578,446,469,534,82,484,1921,902,787,7210,479,37,490,364,66,31,360,485,162,488,605,436,418,473,88,96,7359,1923,604,1925,1924,532,594,649,333,483,8479,476,75,410,7336,7381,7390,7401,7371,7260,4021,711,1927,7184,7391,7320,8471,435,397,468,404,7308,434,323,832,576,619,830,703,704,705,706,712,580,716,717,718,719,7450,857,726,731,835,836,607,608,609,610,611,612,613,614,615,616,617,618,623,624,625,638,639,640,626,627,628,629,630,631,632,633,634,635,636,637,641,642,643,644,645,646,69,432,443,55,401,585,7404,325,349,431,416,689,7445,7451,369,867,7279,864,847,764,524,714,721,794,800,801,810,816,811,809,813,812,806,823,1905,722,727,733,746,7263,7420,7444,900,828,824,767,765,545,8450,392,1902,421,602,407,606,463,7281,7399,7398,7287,7264,7220,7215,7266,7208,7402,7321,7222,7283,7360,7229,7368,859,2968,7249,1941,7403,7414,7228,880,7214,855,7356,7186,868,3015,8484,8482,23,1904,7349,1950,1906,1909,445,60,905,17,7200,8488,450,1938,386,26,440,775,7347,7282,7278,7443,7345,7241,7395,7348,674,2982,7255,883,892,679,304,100,358,529,2985,7375,49,87,673,1936,157,901,16,22,422,388,451,321,190,7424,7306,738,8487,7318,7315,7422,54,720,21,577,389,7354,5111,729,684,620,621,622,587,588,99,871,818,751,808,817,807,826,820,752,904,7250,7242,7224,7335,7394,3010,7240,7423,742,7209,7329,30,385,324,25,510,20,70,374,307,409,486,35,370,97,206,114,419,405,395,81,38,92,305,146,52,93,7187,64,317,420,329,361,356,44,48,86,42,322,29,27,844,348,63,62,79,444,363,308,90'
		,@Environment = 'LOCAL'
		,@IsHaveAtLeastOneOpenDoc = 1
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyIDs (PartyID INT)
	INSERT INTO #PartyIDs (PartyID) SELECT value FROM STRING_SPLIT(@PartyIDs,',')

	CREATE TABLE #Data (
		PartyID			INT,
		PayerName		VARCHAR(50),
		LicenseeCode	VARCHAR(50),
		BaseCurrencyCode VARCHAR(12),
		CurrencyID		INT,
		SettlementType  VARCHAR(50),	-- 0: Invoice settlement, 1: Rebate Settlement
		DocumentNo		VARCHAR(50),
		DocumentID		INT,
		DocumentTypeID	TINYINT,		-- 0: Invoice, 1:Payment
		DocumentType	VARCHAR(200),	-- 0: Invoice, 1:Payment
		DocumentDate	DATETIME,
		InvoiceAmount	MONEY,
		PaymentAmount	MONEY,
		DocumentDetailTypeID TINYINT
	) 

	-- Get all LicenseeCode
	CREATE TABLE #LicenseeCode (PartyID	INT, BaseCurrencyId TINYINT, LicenseeCode VARCHAR(50), IsActive BIT DEFAULT 0 , PayerName VARCHAR(50),BaseCurrencyCode VARCHAR(12))
	INSERT INTO #LicenseeCode (PartyID, BaseCurrencyId, LicenseeCode, PayerName, BaseCurrencyCode)
	SELECT	DISTINCT op.PartyID, 
			op.BaseCurrencyId, 
			op.LicenseeCode, 
			o.PartyName,
			e.Code
	FROM	OAS_PartyBaseCurrency op WITH(NOLOCK)
	INNER JOIN 	#PartyIDs p ON p.PartyID = op.PartyID
	INNER JOIN OAS_party o WITH(NOLOCK) ON o.PartyId = p.PartyId
	INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId

	UPDATE t
	SET t.IsActive =  1
	FROM #LicenseeCode t
	WHERE EXISTS
	(
		SELECT  TOP 1 1 
		FROM    OAS_PartyBaseCurrency op WITH(NOLOCK)
		WHERE   GETDATE() BETWEEN op.FromDate AND  op.ToDate AND t.LicenseeCode = op.LicenseeCode
	)

	-- Insert all normal invoices  AND relation DN, CN, Payment

	-- Normal invoices
	INSERT INTO #Data (PartyID, PayerName, LicenseeCode, CurrencyID, BaseCurrencyCode, SettlementType, DocumentNo, DocumentID, DocumentTypeID, DocumentType, DocumentDate, InvoiceAmount, PaymentAmount, DocumentDetailTypeID)
	SELECT	lc.PartyId, 
			lc.PayerName,
			lc.LicenseeCode, 
			lc.BaseCurrencyId, 
			lc.BaseCurrencyCode,
			inv.SettlementType,
			inv.OfficialInvoiceNo,
			inv.InvoiceHeaderId,
			inv.DocumentTypeID,
			inv.InvTypeName,
			inv.DocumentDate,
			inv.InvoiceAmount,
			inv.PaymentAmount,
			inv.DocumentDetailTypeID
		FROM #LicenseeCode lc  
		OUTER APPLY 
		(
			-- Normal inv
			SELECT  CASE WHEN li.InvoiceType IN (1,6,7) THEN 'Invoice Settlement' ELSE 'Rebate Settlement' END SettlementType,
					li.OfficialInvoiceNo,
					li.InvoiceHeaderId,
					0 AS DocumentTypeID,
					iv.InvTypeName,
					InvoiceDate AS DocumentDate,
					ISNULL(RemainingAmount, Amount) InvoiceAmount,
					NULL AS PaymentAmount,
					li.InvoiceType DocumentDetailTypeID
			FROM	LA_InvoiceHeader li WITH(NOLOCK)
			INNER JOIN LA_InvoiceType iv WITH(NOLOCK)  ON iv.InvTypeId = li.InvoiceType
			WHERE li.InvoiceType IN (1,3,6,7) AND li.StatusId = 0
				AND ISNULL(RemainingAmount, Amount) <> 0
				AND li.Environment = @Environment
				AND li.PartyId = lc.PartyID AND li.CurrencyId = lc.BaseCurrencyId

			UNION ALL

			-- CN, DN
			SELECT  CASE WHEN d.InvoiceType IN (1,6,7) THEN 'Invoice Settlement' ELSE 'Rebate Settlement' END SettlementType,
				li.OfficialInvoiceNo,
				li.InvoiceHeaderId,
				0 AS DocumentTypeID,
				iv.InvTypeName + ' for ' + InvoiceList,
				li.InvoiceDate AS DocumentDate,
				ISNULL(li.RemainingAmount, li.Amount)  InvoiceAmount,
				NULL AS PaymentAmount,
				li.InvoiceType DocumentDetailTypeID
			FROM	LA_InvoiceHeader li WITH(NOLOCK)
			INNER JOIN LA_InvoiceType iv WITH(NOLOCK)  ON iv.InvTypeId = li.InvoiceType
			CROSS APPLY (
				SELECT  MAX(d.InvoiceType) InvoiceType, STRING_AGG(d.OfficialInvoiceNo,', ') AS InvoiceList
				FROM (
					SELECT DISTINCT InvoiceType, OfficialInvoiceNo
					FROM  LA_InvoiceStatement st WITH(NOLOCK) 
					INNER JOIN LA_InvoiceHeader d WITH(NOLOCK) ON st.RefNo = d.OfficialInvoiceNo AND d.InvoiceType IN (1,3,6,7) AND d.StatusId <> -1
					WHERE  li.InvoiceHeaderId = st.InvoiceHeaderId
				) d
			) d
			WHERE li.InvoiceType IN (4,5) AND li.StatusId = 0 
				AND ISNULL(li.RemainingAmount, li.Amount) <> 0
				AND li.Environment = @Environment
				AND li.PartyId = lc.PartyID AND li.CurrencyId = lc.BaseCurrencyId

			UNION ALL

			SELECT  CASE WHEN li.Type IN (0,1) THEN 'Invoice Settlement' ELSE 'Rebate Settlement' END  SettlementType, 
					li.PaymentNo  DocumentNo, 
					li.PaymentId DocumentID, 
					1 AS  DocumentTypeID,
					li.Remark DocumentType,
					ReceivedDate DocumentDate, 
					NULL AS InvoiceAmount,
					Remainingamount PaymentAmount,
					li.Type DocumentDetailTypeID
			FROM	LA_Payment  li WITH(NOLOCK)
			WHERE li.StatusId = 0 
				AND li.Environment = @Environment
				AND li.PartyId = lc.PartyID AND li.CurrencyId = lc.BaseCurrencyId

		) inv

	DELETE x
	FROM #Data x
	INNER JOIN
	(
		SELECT SUM(CASE WHEN DocumentID IS NULL THEN 0 ELSE 1 END) cnt, PartyID, LicenseeCode
		FROM #Data
		GROUP BY PartyID, LicenseeCode
		HAVING  SUM(CASE WHEN DocumentID IS NULL THEN 0 ELSE 1 END) = 0
			
	)del_ ON x.PartyID  = del_.PartyID  AND x.LicenseeCode = del_.LicenseeCode
	INNER JOIN #LicenseeCode lc ON lc.PartyID = del_.PartyID AND lc.LicenseeCode = del_.LicenseeCode AND lc.IsActive = 0


	IF @IsHaveAtLeastOneOpenDoc = 1
		DELETE x
		FROM #Data x
		INNER JOIN
		(
			SELECT SUM(CASE WHEN DocumentID IS NULL THEN 0 ELSE 1 END) cnt, PartyID, LicenseeCode, CurrencyID
			FROM #Data
			GROUP BY PartyID, LicenseeCode, CurrencyID
			HAVING  SUM(CASE WHEN DocumentID IS NULL THEN 0 ELSE 1 END) = 0
			
		)del_ ON x.PartyID  = del_.PartyID AND x.LicenseeCode = del_.LicenseeCode AND x.CurrencyID = del_.CurrencyID

	SELECT PartyID, PayerName, LicenseeCode, BaseCurrencyCode ,SettlementType, DocumentNo, DocumentID, DocumentTypeID, DocumentType, DocumentDate, InvoiceAmount, PaymentAmount, DocumentDetailTypeID FROM #Data
	ORDER BY PartyID, LicenseeCode, SettlementType, DocumentDate

	DROP TABLE #PartyIDs
	DROP TABLE #Data
	DROP TABLE #LicenseeCode

END
GO