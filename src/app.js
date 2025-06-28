import express from 'express';
import cors from 'cors';
import { BedrockRuntimeClient, InvokeModelCommand } from '@aws-sdk/client-bedrock-runtime';
import * as dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const bedrock = new BedrockRuntimeClient({
    region: process.env.AWS_REGION || 'us-east-1',
});

app.post('/extract', async (req, res) => {
    const { description } = req.body;

    if (!description || typeof description !== 'string') {
        return res.status(400).json({ error: 'Invalid request. Must include "description" string.' });
    }

    const prompt = `
You are an assistant that extracts the main composed message from email replies.

Instructions:
- Extract ONLY the text that begins with a **salutation** like “Hi”, “Hello”, “Hey”, etc. It must **start exactly at that greeting**.
- Continue extracting text **until the closing line that contains a sign-off**, such as “Thanks”, “Thank you”, “Regards”, or the sender's **name** (e.g., "Meghan", "John", etc.).
- **Do NOT include any previous email replies, headers, or signatures.**
- **Do NOT extract anything before the salutation or after the closing name/sign-off.**
- The result must be natural and human-readable, maintaining all original **line breaks** and paragraph formatting.

Email Chain:
"""${description}"""
`;

    const payload = {
        anthropic_version: 'bedrock-2023-05-31',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 1024,
        temperature: 0,
        top_p: 1,
    };

    const command = new InvokeModelCommand({
        modelId: 'anthropic.claude-3-sonnet-20240229-v1:0',
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify(payload),
    });

    try {
        const response = await bedrock.send(command);
        const body = JSON.parse(Buffer.from(response.body).toString('utf-8'));
        const content = body.content?.[0]?.text?.trim();

        return res.json({ content });
    } catch (error) {
        console.error('Error invoking Bedrock:', error);
        return res.status(500).json({ error: 'Failed to extract email.' });
    }
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
