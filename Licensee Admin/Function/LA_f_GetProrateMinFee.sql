/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_GetProrateMinFee]
(
	@PartyIds	VARCHAR(MAX)
	,@FromDate	DATETIME
	,@ToDate	DATETIME
)
RETURNS @MinFee TABLE
(
	RowId INT
	,PartyId INT
	,ProductId INT
	,BaseCurrencyId INT
	,GroupId INT
	,GroupMinFeeId INT
	,FeeTypeId TINYINT
	,IsPrimary BIT
	,FromDate DATE
	,ToDate DATE
	,MinFee MONEY DEFAULT (0)
	,ProrateMinFee MONEY DEFAULT (0)
)
AS

/*
	Created: 20210909@Percy
	DB: DBLIC-bodb_Licensee
	Task: Core function - Get Prorate Min Fee

	Revisions:
		- 20210909@Percy: Initialize SP [RedmineID: #157652]
*/

BEGIN
	DECLARE @FirstDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
	DECLARE @LastDate DATE = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FirstDate))
	DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

	DECLARE @IndividualMinFee TABLE (RowId INT, GroupId INT, FeeTypeId TINYINT, PartyId INT, ProductId INT, BaseCurrencyId INT, FromDate DATE, ToDate DATE, MinFee MONEY)
	DECLARE @tmpDate TABLE (PartyId INT, ProductId INT, FromDate DATE, ToDate DATE)

	-- Group Min Fee
	INSERT INTO @MinFee (FeeTypeId, GroupMinFeeId, PartyId, ProductId, BaseCurrencyId, IsPrimary, MinFee, FromDate, ToDate, RowId, GroupId)
	SELECT 1, GroupMinFeeId, PartyId, ISNULL(ProductId, 0), ISNULL(CurrencyId, 6), IsPrimary, MinFee, FromDate, ToDate, RowId, RowId
	FROM (
		SELECT m.GroupMinFeeId, m.PartyId, m.ProductId, m.CurrencyId, m.IsPrimary, m.MinFee, m.FromDate, m.ToDate, ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY FromDate) AS RowId
		FROM (
			SELECT a.PartyId, a.IsPrimary, a.GroupMinFeeId, d.ProductId, d.CurrencyId
				,CASE WHEN a.IsPrimary = 1 THEN ISNULL(d.MinimumFee, 0) ELSE 0 END AS MinFee
				,CASE WHEN h.FromDate < @FirstDate THEN @FirstDate ELSE h.FromDate END AS FromDate
				,CASE WHEN h.ToDate > @LastDate THEN @LastDate ELSE h.ToDate END AS ToDate
				,ROW_NUMBER() OVER(PARTITION BY a.PartyId, a.GroupMinFeeId, d.ProductId ORDER BY d.ToDate DESC) AS RN
			FROM dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
				INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
				LEFT JOIN dbo.LA_GroupMinFeeDetail d WITH (NOLOCK) ON a.GroupMinFeeId = d.GroupMinFeeId AND d.FromDate <= @LastDate AND d.ToDate >= @FirstDate
			WHERE h.FromDate <= @LastDate AND h.ToDate >= @FirstDate
				AND ',' + @PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), a.PartyId) + ',%'
		) m
		WHERE m.RN = 1
	) t

	-- Individual Min Fee
	INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, BaseCurrencyId, MinFee, FromDate, ToDate, RowId, GroupId)
	SELECT 0 AS FeeTypeId, PartyId, ProductId, CurrencyId, MinFee, FromDate, ToDate, RowId, RowId
	FROM (
		SELECT m.PartyId, m.ProductId, m.CurrencyId, m.FeeAmount AS MinFee
			,CASE WHEN m.FromDate < @FirstDate THEN @FirstDate ELSE m.FromDate END AS FromDate
			,CASE WHEN m.ToDate > @LastDate THEN @LastDate ELSE m.ToDate END AS ToDate
			,ROW_NUMBER() OVER(PARTITION BY m.PartyId, m.ProductId ORDER BY m.FromDate) AS RowId
		FROM dbo.LA_MinFee m WITH (NOLOCK)
		WHERE m.FeeTypeId = 1 AND m.FromDate <= @LastDate AND m.ToDate >= @FirstDate
			AND ',' + @PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), m.PartyId) + ',%'
	) t

	-- Waive (under Individual Min Fee)
	INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, FromDate, ToDate, RowId, GroupId)
	SELECT w.FeeTypeId, w.PartyId, w.ProductId
		,CASE WHEN w.FromDate < m.FromDate THEN m.FromDate ELSE w.FromDate END AS FromDate
		,CASE WHEN w.ToDate > m.ToDate THEN m.ToDate ELSE w.ToDate END AS ToDate
		,ROW_NUMBER() OVER(PARTITION BY w.PartyId, w.ProductId ORDER BY w.FromDate) AS RowId
		,m.GroupId
	FROM @IndividualMinFee m
		INNER JOIN dbo.LA_MinFee w WITH (NOLOCK) ON m.PartyId = w.PartyId AND m.ProductId = w.ProductId
	WHERE w.FeeTypeId = 2 AND m.FromDate <= w.ToDate AND m.ToDate >= w.FromDate

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT t1.PartyId, t1.ProductId, t2.FromDate, t2.ToDate
	FROM (SELECT PartyId, ProductId, MIN(FromDate) AS FromDate, MAX(ToDate) AS ToDate FROM @IndividualMinFee WHERE FeeTypeId = 2 GROUP BY PartyId, ProductId) t1
		CROSS APPLY (
			SELECT @FirstDate AS FromDate, DATEADD(DAY, -1, t1.FromDate) AS ToDate WHERE t1.FromDate > @FirstDate
			UNION ALL SELECT DATEADD(DAY, 1, t1.ToDate) AS FromDate, @LastDate AS ToDate WHERE t1.ToDate < @LastDate
		) t2

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT t1.PartyId, t1.ProductId, DATEADD(DAY, 1, t1.ToDate) AS FromDate, DATEADD(DAY, -1, t2.FromDate) AS ToDate
	FROM @IndividualMinFee t1
		INNER JOIN @IndividualMinFee t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId AND t1.FeeTypeId = t2.FeeTypeId
	WHERE t1.FeeTypeId = 2 AND t1.RowId + 1 = t2.RowId AND t1.ToDate < DATEADD(DAY, -1, t2.FromDate)

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT m.PartyId, m.ProductId, @FirstDate, @LastDate
	FROM @IndividualMinFee m WHERE m.FeeTypeId = 0
		AND NOT EXISTS (SELECT 1 FROM @tmpDate t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId)
	GROUP BY m.PartyId, m.ProductId
		
	INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, BaseCurrencyId, MinFee, RowId, GroupId, FromDate, ToDate)
	SELECT 1 AS FeeTypeId, m.PartyId, m.ProductId, m.BaseCurrencyId, m.MinFee, m.RowId, m.GroupId
		,CASE WHEN m.FromDate < t.FromDate THEN t.FromDate ELSE m.FromDate END AS FromDate
		,CASE WHEN m.ToDate > t.ToDate THEN t.ToDate ELSE m.ToDate END AS ToDate
	FROM @IndividualMinFee m
		INNER JOIN @tmpDate t ON m.PartyId = t.PartyId AND m.ProductId = t.ProductId AND m.FromDate <= t.ToDate AND m.ToDate >= t.FromDate
	WHERE m.FeeTypeId = 0

	DELETE @IndividualMinFee WHERE FeeTypeId = 0
	DELETE @tmpDate

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT t1.PartyId, t1.ProductId, t2.FromDate, t2.ToDate
	FROM (SELECT PartyId, ProductId, MIN(FromDate) AS FromDate, MAX(ToDate) AS ToDate FROM @MinFee GROUP BY PartyId, ProductId) t1
		CROSS APPLY (
			SELECT @FirstDate AS FromDate, DATEADD(DAY, -1, t1.FromDate) AS ToDate WHERE t1.FromDate > @FirstDate
			UNION ALL SELECT DATEADD(DAY, 1, t1.ToDate) AS FromDate, @LastDate AS ToDate WHERE t1.ToDate < @LastDate
		) t2

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT t1.PartyId, t1.ProductId, DATEADD(DAY, 1, t1.ToDate) AS FromDate, DATEADD(DAY, -1, t2.FromDate) AS ToDate
	FROM @MinFee t1
		INNER JOIN @MinFee t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
	WHERE t1.RowId + 1 = t2.RowId AND t1.ToDate < DATEADD(DAY, -1, t2.FromDate)

	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate)
	SELECT m.PartyId, m.ProductId, @FirstDate, @LastDate
	FROM @IndividualMinFee m WHERE m.FeeTypeId = 1
		AND NOT EXISTS (SELECT 1 FROM @tmpDate t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId)
		AND NOT EXISTS (SELECT 1 FROM @MinFee t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId)
	GROUP BY m.PartyId, m.ProductId

	INSERT INTO @MinFee (FeeTypeId, GroupMinFeeId, PartyId, ProductId, BaseCurrencyId, IsPrimary, MinFee, FromDate, ToDate, RowId, GroupId)
	SELECT m.FeeTypeId, -m.PartyId AS GroupMinFeeId, m.PartyId, m.ProductId, m.BaseCurrencyId, 1 AS IsPrimary, m.MinFee
		,CASE WHEN m.FromDate < t.FromDate THEN t.FromDate ELSE m.FromDate END AS FromDate
		,CASE WHEN m.ToDate > t.ToDate THEN t.ToDate ELSE m.ToDate END AS ToDate
		,m.RowId, m.GroupId
	FROM @IndividualMinFee m
		INNER JOIN @tmpDate t ON m.PartyId = t.PartyId AND m.ProductId = t.ProductId AND m.FromDate <= t.ToDate AND m.ToDate >= t.FromDate

	UPDATE m
	SET m.FromDate = CASE
						WHEN d.FromDate IS NULL THEN '2000-01-01'
						WHEN d.FromDate < @FirstDate THEN @FirstDate
						ELSE d.FromDate END
		,m.ToDate = CASE
						WHEN d.ToDate IS NULL THEN '2000-01-01'
						WHEN d.ToDate > @LastDate THEN @LastDate
						ELSE d.ToDate END
	FROM @MinFee m
		OUTER APPLY (
			SELECT TOP 1 d.FromDate, d.ToDate
			FROM dbo.LA_GroupMinFeeDetail d WITH (NOLOCK)
			WHERE m.GroupMinFeeId = d.GroupMinFeeId AND m.ProductId = d.ProductId
				AND d.FromDate <= @LastDate AND d.ToDate >= @FirstDate
			ORDER BY d.ToDate DESC
		) d
	WHERE m.GroupMinFeeId > 0

	DELETE @MinFee WHERE FromDate > @ToDate OR ToDate < @FromDate
	
	UPDATE @MinFee
	SET FromDate = CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END
		,ToDate = CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
	WHERE FromDate < @FromDate OR ToDate > @ToDate

	-- Update Prorate Min Fee
	UPDATE t
	SET t.ProrateMinFee = t.MinFee * 1.0 * p.TotalDays / @DaysInMonth
	FROM @MinFee t
		INNER JOIN (
			SELECT PartyId, ProductId, GroupMinFeeId, GroupId, SUM(DATEDIFF(DAY, FromDate, ToDate) + 1) AS TotalDays
			FROM @MinFee
			WHERE FeeTypeId = 1 AND IsPrimary = 1
			GROUP BY PartyId, ProductId, GroupMinFeeId, GroupId
		) p ON t.GroupId = p.GroupId AND t.GroupMinFeeId = p.GroupMinFeeId AND t.PartyId = p.PartyId AND t.ProductId = p.ProductId
	
	RETURN
END
GO