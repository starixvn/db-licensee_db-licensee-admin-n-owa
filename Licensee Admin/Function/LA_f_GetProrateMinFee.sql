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
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
*/

BEGIN
	DECLARE @FirstDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
	DECLARE @LastDate DATE = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FirstDate))
	DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

	DECLARE @IndividualMinFee TABLE (RowId INT, GroupId INT, FeeTypeId TINYINT, PartyId INT, ProductId INT, BaseCurrencyId INT, FromDate DATE, ToDate DATE, MinFee MONEY)
	DECLARE @tmpDate TABLE (PartyId INT, ProductId INT, FromDate DATE, ToDate DATE, BaseCurrencyId INT, MinFee MONEY, GroupId INT)
	DECLARE @WrongSetting TABLE (PartyId INT, ProductId INT)

	-- Include primary licensee if input secondary licensee
	DECLARE @_PartyIds VARCHAR(MAX)
	SELECT  @_PartyIds = COALESCE(@_PartyIds + ',', '') + CONVERT(VARCHAR(20), a.PartyId)
	FROM dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
		INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
	WHERE h.FromDate <= @LastDate AND h.ToDate >= @FirstDate
		AND EXISTS (
			SELECT 1 FROM dbo.LA_GroupMinFeeAssignment ga WITH (NOLOCK)
			WHERE a.GroupMinFeeId = ga.GroupMinFeeId
				AND ',' + @PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), ga.PartyId) + ',%'
		)

	SELECT @_PartyIds = ISNULL(@_PartyIds + ',', '') + @PartyIds
		
	-- Group Min Fee
	;WITH CTE_GroupMinFee AS
	(
		SELECT a.PartyId, a.IsPrimary, a.GroupMinFeeId, d.ProductId, d.CurrencyId
			,CASE WHEN a.IsPrimary = 1 THEN ISNULL(d.MinimumFee, 0) ELSE 0 END AS MinFee
			,CASE WHEN h.FromDate < @FirstDate THEN @FirstDate ELSE h.FromDate END AS H_FromDate
			,CASE WHEN h.ToDate > @LastDate THEN @LastDate ELSE h.ToDate END AS H_ToDate
			,CASE WHEN d.FromDate < @FirstDate THEN @FirstDate ELSE d.FromDate END AS D_FromDate
			,CASE WHEN d.ToDate > @LastDate THEN @LastDate ELSE d.ToDate END AS D_ToDate
			,ROW_NUMBER() OVER(PARTITION BY a.PartyId, a.GroupMinFeeId, d.ProductId ORDER BY d.ToDate DESC) AS RN
		FROM dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
			INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
			INNER JOIN dbo.LA_GroupMinFeeDetail d WITH (NOLOCK) ON a.GroupMinFeeId = d.GroupMinFeeId
		WHERE h.FromDate <= @LastDate AND h.ToDate >= @FirstDate
			AND ',' + @_PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), a.PartyId) + ',%'
	)
	INSERT INTO @MinFee (RowId, GroupId, FeeTypeId, GroupMinFeeId, PartyId, ProductId, BaseCurrencyId, IsPrimary, MinFee, FromDate, ToDate)
	SELECT RowId, RowId, 1, GroupMinFeeId, PartyId, ProductId, CurrencyId, IsPrimary, MinFee
		,CASE WHEN IsWrongSetting = 1 THEN @FirstDate ELSE FromDate END
		,CASE WHEN IsWrongSetting = 1 THEN @LastDate ELSE ToDate END
	FROM (
		SELECT GroupMinFeeId, PartyId, ProductId, CurrencyId, IsPrimary, MinFee, H_FromDate AS FromDate, H_ToDate AS ToDate
			,CASE WHEN D_FromDate <> H_FromDate OR D_ToDate <> H_ToDate THEN 1 ELSE 0 END AS IsWrongSetting
			,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY D_FromDate) AS RowId
		FROM CTE_GroupMinFee
		WHERE RN = 1
	) t

	-- If wrong setting --> get latest setting for full month
	INSERT INTO @WrongSetting (PartyId, ProductId)
	SELECT DISTINCT g1.PartyId, g1.ProductId
	FROM @MinFee g1
		INNER JOIN @MinFee g2 ON g1.PartyId = g2.PartyId AND g1.ProductId = g2.ProductId AND g1.RowId = g2.RowId + 1
	WHERE g1.FromDate <> DATEADD(DAY, 1, g2.ToDate)

	IF EXISTS (SELECT 1 FROM @WrongSetting)
	BEGIN
		UPDATE g
		SET g.FromDate = CASE WHEN g.RN = 1 THEN @FirstDate ELSE '2000-01-01' END
			,g.ToDate = CASE WHEN g.RN = 1 THEN @LastDate ELSE '2000-01-01' END
		FROM (
			SELECT g.FromDate, g.ToDate, ROW_NUMBER() OVER(PARTITION BY g.PartyId, g.ProductId ORDER BY g.RowId DESC) AS RN
			FROM @MinFee g
				INNER JOIN @WrongSetting w ON g.PartyId = w.PartyId AND g.ProductId = w.ProductId
		) g

		DELETE @WrongSetting
		DELETE @MinFee WHERE FromDate = '2000-01-01'
	END
	
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
			AND ',' + @_PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), m.PartyId) + ',%'
	) t

	-- Merge setting
	;WITH CTE_Party AS (
		SELECT DISTINCT t1.PartyId, t1.ProductId
		FROM @IndividualMinFee t1
			INNER JOIN @IndividualMinFee t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
		WHERE t1.RowId + 1 = t2.RowId AND DATEADD(DAY, 1, t1.ToDate) = t2.FromDate
	)
	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate, BaseCurrencyId, MinFee)
	SELECT m.PartyId, m.ProductId, m.FromDate, m.ToDate, m.BaseCurrencyId, m.MinFee
	FROM CTE_Party p
		INNER JOIN @IndividualMinFee m ON p.PartyId = m.PartyId AND p.ProductId = p.ProductId

	IF EXISTS (SELECT 1 FROM @tmpDate)
	BEGIN
		WHILE EXISTS (
			SELECT 1
			FROM @tmpDate t1
				INNER JOIN @tmpDate t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
			WHERE DATEADD(DAY, 1, t1.ToDate) = t2.FromDate
		)
		BEGIN
			UPDATE t1
			SET t1.ToDate = t2.ToDate
			FROM @tmpDate t1
				INNER JOIN @tmpDate t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
			WHERE DATEADD(DAY, 1, t1.ToDate) = t2.FromDate
		END

		DELETE @IndividualMinFee
		FROM @IndividualMinFee m
		WHERE EXISTS (SELECT 1 FROM @tmpDate t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId)

		INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, BaseCurrencyId, MinFee, FromDate, ToDate, RowId, GroupId)
		SELECT 0 AS FeeTypeId, PartyId, ProductId, BaseCurrencyId, MinFee, FromDate, ToDate
			,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY FromDate) AS RowId
			,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY FromDate) AS GroupId
		FROM (
			SELECT PartyId, ProductId, BaseCurrencyId, MinFee, FromDate, ToDate
				,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId, ToDate ORDER BY FromDate) AS RN
			FROM @tmpDate
		) t
		WHERE RN = 1

		DELETE @tmpDate
	END

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

	-- Merge setting
	;WITH CTE_Party AS (
		SELECT DISTINCT t1.PartyId, t1.ProductId
		FROM @IndividualMinFee t1
			INNER JOIN @IndividualMinFee t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId AND t1.FeeTypeId = t2.FeeTypeId
		WHERE t1.RowId + 1 = t2.RowId AND DATEADD(DAY, 1, t1.ToDate) = t2.FromDate AND t1.FeeTypeId = 2
	)
	INSERT INTO @tmpDate (PartyId, ProductId, FromDate, ToDate, GroupId)
	SELECT m.PartyId, m.ProductId, m.FromDate, m.ToDate, m.GroupId
	FROM CTE_Party p
		INNER JOIN @IndividualMinFee m ON p.PartyId = m.PartyId AND p.ProductId = p.ProductId AND m.FeeTypeId = 2

	IF EXISTS (SELECT 1 FROM @tmpDate)
	BEGIN
		WHILE EXISTS (
			SELECT 1
			FROM @tmpDate t1
				INNER JOIN @tmpDate t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
			WHERE DATEADD(DAY, 1, t1.ToDate) = t2.FromDate
		)
		BEGIN
			UPDATE t1
			SET t1.ToDate = t2.ToDate
			FROM @tmpDate t1
				INNER JOIN @tmpDate t2 ON t1.PartyId = t2.PartyId AND t1.ProductId = t2.ProductId
			WHERE DATEADD(DAY, 1, t1.ToDate) = t2.FromDate
		END

		DELETE @IndividualMinFee
		FROM @IndividualMinFee m
		WHERE EXISTS (SELECT 1 FROM @tmpDate t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId)
			AND m.FeeTypeId = 2

		INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, FromDate, ToDate, GroupId, RowId)
		SELECT 2 AS FeeTypeId, PartyId, ProductId, FromDate, ToDate, GroupId
			,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY FromDate) AS RowId
		FROM (
			SELECT PartyId, ProductId, FromDate, ToDate, GroupId
				,ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId, ToDate ORDER BY FromDate) AS RN
			FROM @tmpDate
		) t
		WHERE RN = 1

		DELETE @tmpDate
	END
	
	-- Get Waive for Group (secondary will follow primary)
	;WITH CTE_GroupMinFee AS (
		SELECT PartyId, ProductId, FromDate, ToDate, GroupMinFeeId, RowId, ROW_NUMBER() OVER(PARTITION BY PartyId, ProductId ORDER BY RowId DESC) AS RN
		FROM @MinFee
		WHERE IsPrimary = 1
	)
	INSERT INTO @MinFee (RowId, PartyId, ProductId, BaseCurrencyId, GroupId, GroupMinFeeId, FeeTypeId, IsPrimary, FromDate, ToDate, MinFee)
	SELECT m.RowId, g.PartyId, g.ProductId, m.BaseCurrencyId, m.GroupId, -m.PartyId, m.FeeTypeId, g.IsPrimary, m.FromDate, m.ToDate, m.MinFee
	FROM CTE_GroupMinFee p
		INNER JOIN @IndividualMinFee m ON p.PartyId = m.PartyId AND p.ProductId = m.ProductId AND m.FeeTypeId = 2
		CROSS APPLY (SELECT PartyId, ProductId, IsPrimary FROM @MinFee g WHERE g.GroupMinFeeId = p.GroupMinFeeId) g
	WHERE
		(
			(p.RowId = 1 AND p.FromDate > @FirstDate AND m.FromDate = @FirstDate AND p.FromDate = DATEADD(DAY, 1, m.ToDate))
			OR (p.RN = 1 AND p.ToDate < @LastDate AND m.ToDate = @LastDate AND p.ToDate = DATEADD(DAY, -1, m.FromDate))
		)

	-- If wrong setting --> get latest setting for full month
	INSERT INTO @WrongSetting (PartyId, ProductId)
	SELECT PartyId, ProductId
	FROM @MinFee
	GROUP BY PartyId, ProductId
	HAVING MIN(FromDate) > @FirstDate OR MAX(ToDate) < @LastDate
	
	IF EXISTS (SELECT 1 FROM @WrongSetting)
	BEGIN
		UPDATE g
		SET g.FromDate = CASE WHEN g.RN = 1 THEN @FirstDate ELSE '2000-01-01' END
			,g.ToDate = CASE WHEN g.RN = 1 THEN @LastDate ELSE '2000-01-01' END
		FROM (
			SELECT g.FromDate, g.ToDate, ROW_NUMBER() OVER(PARTITION BY g.PartyId, g.ProductId ORDER BY CASE WHEN g.GroupMinFeeId > 0 THEN 0 ELSE 1 END, g.RowId DESC) AS RN
			FROM @MinFee g
				INNER JOIN @WrongSetting w ON g.PartyId = w.PartyId AND g.ProductId = w.ProductId
		) g

		DELETE @WrongSetting
		DELETE @MinFee WHERE FromDate = '2000-01-01'
	END

	-- Insert individual min fee & waive for case no group setting
	DELETE @IndividualMinFee
	FROM @IndividualMinFee m
		INNER JOIN @MinFee g ON m.PartyId = g.PartyId AND m.ProductId = g.ProductId

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
		AND NOT EXISTS (SELECT 1 FROM @IndividualMinFee t WHERE m.PartyId = t.PartyId AND m.ProductId = t.ProductId AND t.FeeTypeId = 2)
	GROUP BY m.PartyId, m.ProductId
		
	INSERT INTO @IndividualMinFee (FeeTypeId, PartyId, ProductId, BaseCurrencyId, MinFee, RowId, GroupId, FromDate, ToDate)
	SELECT 1 AS FeeTypeId, m.PartyId, m.ProductId, m.BaseCurrencyId, m.MinFee, m.RowId, m.GroupId
		,CASE WHEN m.FromDate < t.FromDate THEN t.FromDate ELSE m.FromDate END AS FromDate
		,CASE WHEN m.ToDate > t.ToDate THEN t.ToDate ELSE m.ToDate END AS ToDate
	FROM @IndividualMinFee m
		INNER JOIN @tmpDate t ON m.PartyId = t.PartyId AND m.ProductId = t.ProductId AND m.FromDate <= t.ToDate AND m.ToDate >= t.FromDate
	WHERE m.FeeTypeId = 0

	DELETE @IndividualMinFee WHERE FeeTypeId = 0

	INSERT INTO @MinFee (FeeTypeId, GroupMinFeeId, PartyId, ProductId, BaseCurrencyId, IsPrimary, MinFee, FromDate, ToDate, RowId, GroupId)
	SELECT FeeTypeId, -PartyId, PartyId, ProductId, BaseCurrencyId, 1 AS IsPrimary, MinFee, FromDate, ToDate, RowId, GroupId
	FROM @IndividualMinFee

	-- Keep selected licensees
	DELETE @MinFee WHERE ',' + @PartyIds + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), PartyId) + ',%'

	UPDATE m
	SET m.FromDate = CASE
						WHEN c.FromDate IS NULL THEN '2000-01-01'
						WHEN m.FromDate < c.FromDate THEN c.FromDate
						ELSE m.FromDate END
		,m.ToDate = CASE
						WHEN c.ToDate IS NULL THEN '2000-01-01'
						WHEN m.ToDate > c.ToDate THEN c.ToDate
						ELSE m.ToDate END
	FROM @MinFee m
		OUTER APPLY (
			SELECT MIN(c.FromDate) AS FromDate, MAX(c.ToDate) AS ToDate
			FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			WHERE m.PartyId = c.FromParty AND m.ProductId = c.ProductId
				AND c.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z)
				AND c.ChargeType NOT IN (2, 3)
		) c

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